// NowPlayingService.swift
// MacIsland
//
// Bridges into the private MRMediaRemote framework to fetch now-playing info
// (artist, title, album art) from any media source (Spotify, Apple Music, etc.).
//
// WHY MRMediaRemote instead of MPNowPlayingInfoCenter?
// - MPNowPlayingInfoCenter is for *publishing* now-playing info (used by media apps).
// - MRMediaRemote is the private framework that *reads* the system-wide now-playing
//   state — exactly what the Control Center and Touch Bar use internally.
// - We dynamically load it to avoid linking against a private framework directly,
//   which keeps the binary safe if Apple changes the framework path.

import AppKit
import Combine

// MARK: - MRMediaRemote Dynamic Bindings

/// Typedefs for the C-function signatures we load from MRMediaRemote.framework.
private typealias MRMediaRemoteGetNowPlayingInfoFunction =
    @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void

private typealias MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction =
    @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void

private typealias MRMediaRemoteRegisterForNowPlayingNotificationsFunction =
    @convention(c) (DispatchQueue) -> Void

/// MRMediaRemoteSendCommand: sends playback commands to the active media app.
/// Command values: 0=play, 1=pause, 2=togglePlayPause, 3=stop, 4=nextTrack, 5=previousTrack
private typealias MRMediaRemoteSendCommandFunction =
    @convention(c) (UInt32, AnyObject?) -> Bool

/// MRMediaRemoteGetNowPlayingApplicationPID: resolves the PID of the app providing now-playing info.
private typealias MRMediaRemoteGetNowPlayingApplicationPIDFunction =
    @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void

/// Known notification name strings from MRMediaRemote.
private let kMRMediaRemoteNowPlayingInfoDidChangeNotification =
    NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification")
private let kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification =
    NSNotification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")

/// Known dictionary keys in the now-playing info dictionary.
private let kMRMediaRemoteNowPlayingInfoTitle = "kMRMediaRemoteNowPlayingInfoTitle"
private let kMRMediaRemoteNowPlayingInfoArtist = "kMRMediaRemoteNowPlayingInfoArtist"
private let kMRMediaRemoteNowPlayingInfoAlbum = "kMRMediaRemoteNowPlayingInfoAlbum"
private let kMRMediaRemoteNowPlayingInfoArtworkData = "kMRMediaRemoteNowPlayingInfoArtworkData"

// MARK: - NowPlayingInfo Model

struct NowPlayingInfo: Equatable {
    let title: String
    let artist: String
    let album: String
    let artwork: NSImage?
    let isPlaying: Bool

    static let empty = NowPlayingInfo(title: "", artist: "", album: "", artwork: nil, isPlaying: false)

    static func == (lhs: NowPlayingInfo, rhs: NowPlayingInfo) -> Bool {
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.album == rhs.album &&
        lhs.isPlaying == rhs.isPlaying
    }
}

// MARK: - NowPlayingService

@MainActor
final class NowPlayingService: ObservableObject {

    @Published private(set) var nowPlaying: NowPlayingInfo = .empty

    // Resolved function pointers from MRMediaRemote.
    private var getNowPlayingInfo: MRMediaRemoteGetNowPlayingInfoFunction?
    private var getIsPlaying: MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction?
    private var registerForNotifications: MRMediaRemoteRegisterForNowPlayingNotificationsFunction?
    private var sendCommand: MRMediaRemoteSendCommandFunction?
    private var getNowPlayingPID: MRMediaRemoteGetNowPlayingApplicationPIDFunction?

    private var observers: [NSObjectProtocol] = []

    /// Polling timer as a fallback in case notifications don't fire reliably.
    private var pollTimer: Timer?

    init() {
        loadMRMediaRemote()
        startObserving()
        fetchNowPlaying()
        print("[MacIsland] NowPlayingService init: info=\(getNowPlayingInfo != nil), playing=\(getIsPlaying != nil), send=\(sendCommand != nil), pid=\(getNowPlayingPID != nil)")
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        pollTimer?.invalidate()
    }

    // MARK: - Dynamic Loading

    /// Dynamically load MRMediaRemote.framework from its known system path.
    /// This avoids a hard link against a private framework.
    private func loadMRMediaRemote() {
        let bundlePath = "/System/Library/PrivateFrameworks/MediaRemote.framework"
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, URL(fileURLWithPath: bundlePath) as CFURL) else {
            print("[MacIsland] Failed to load MRMediaRemote.framework")
            return
        }

        // Resolve: MRMediaRemoteGetNowPlayingInfo(dispatch_queue_t, callback)
        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString) {
            getNowPlayingInfo = unsafeBitCast(ptr, to: MRMediaRemoteGetNowPlayingInfoFunction.self)
        }

        // Resolve: MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_queue_t, callback)
        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying" as CFString) {
            getIsPlaying = unsafeBitCast(ptr, to: MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction.self)
        }

        // Resolve: MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_queue_t)
        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString) {
            registerForNotifications = unsafeBitCast(ptr, to: MRMediaRemoteRegisterForNowPlayingNotificationsFunction.self)
        }

        // Resolve: MRMediaRemoteSendCommand(command, options) -> Bool
        // Used to send play/pause/next/previous commands to the active media app.
        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
            sendCommand = unsafeBitCast(ptr, to: MRMediaRemoteSendCommandFunction.self)
        }

        // Resolve: MRMediaRemoteGetNowPlayingApplicationPID(dispatch_queue_t, callback)
        // Used to find which app is playing so we can activate it on album art tap.
        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationPID" as CFString) {
            getNowPlayingPID = unsafeBitCast(ptr, to: MRMediaRemoteGetNowPlayingApplicationPIDFunction.self)
        }
    }

    // MARK: - Observation

    private func startObserving() {
        // Register for system now-playing change notifications.
        registerForNotifications?(DispatchQueue.main)

        let infoObserver = NotificationCenter.default.addObserver(
            forName: kMRMediaRemoteNowPlayingInfoDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.fetchNowPlaying()
            }
        }

        let playingObserver = NotificationCenter.default.addObserver(
            forName: kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.fetchNowPlaying()
            }
        }

        observers = [infoObserver, playingObserver]

        // Fallback poll every 3 seconds — some apps (Spotify) occasionally miss notifications.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchNowPlaying()
            }
        }
    }

    // MARK: - Fetch

    // MARK: - Playback Commands

    /// Toggle play/pause on the active media app.
    func togglePlayPause() {
        _ = sendCommand?(2, nil)  // 2 = togglePlayPause
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.fetchNowPlaying()
        }
    }

    /// Skip to the next track.
    func nextTrack() {
        _ = sendCommand?(4, nil)  // 4 = nextTrack
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.fetchNowPlaying()
        }
    }

    /// Skip to the previous track.
    func previousTrack() {
        _ = sendCommand?(5, nil)  // 5 = previousTrack
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.fetchNowPlaying()
        }
    }

    /// Resolve the PID of the app currently providing now-playing info.
    func getNowPlayingAppPID(completion: @escaping (Int32) -> Void) {
        getNowPlayingPID?(DispatchQueue.main, completion)
    }

    // MARK: - Fetch

    func fetchNowPlaying() {
        // Fetch track info first, then playback state.
        // Flattened callback structure to avoid nested Task/weak-self failures.
        getNowPlayingInfo?(DispatchQueue.main) { [weak self] info in
            guard let self else { return }

            let title = info[kMRMediaRemoteNowPlayingInfoTitle] as? String ?? ""
            let artist = info[kMRMediaRemoteNowPlayingInfoArtist] as? String ?? ""
            let album = info[kMRMediaRemoteNowPlayingInfoAlbum] as? String ?? ""

            var artwork: NSImage? = nil
            if let artworkData = info[kMRMediaRemoteNowPlayingInfoArtworkData] as? Data {
                artwork = NSImage(data: artworkData)
            }

            // Now get playback state
            self.getIsPlaying?(DispatchQueue.main) { [weak self] isPlaying in
                guard let self else { return }

                let newInfo = NowPlayingInfo(
                    title: title,
                    artist: artist,
                    album: album,
                    artwork: artwork,
                    isPlaying: isPlaying
                )

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.nowPlaying != newInfo {
                        self.nowPlaying = newInfo
                    }
                }
            }
        }
    }
}
