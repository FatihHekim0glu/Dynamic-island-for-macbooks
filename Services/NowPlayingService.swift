// NowPlayingService.swift
// MacIsland
//
// Maximum-speed now-playing service.
// - Pre-compiled NSAppleScript runs on main thread (~5ms, no async overhead)
// - Optimistic UI: play/pause flips instantly
// - Track info and artwork decoupled (info appears first, art loads async)
// - 0.5s polling, 100ms post-command refresh

import AppKit
import Combine

// MARK: - MRMediaRemote (Command Sending Only)

private typealias MRMediaRemoteSendCommandFunction =
    @convention(c) (UInt32, AnyObject?) -> Bool

private typealias MRMediaRemoteGetNowPlayingApplicationPIDFunction =
    @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void

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

// MARK: - Supported Media Apps

private enum MediaApp: String, CaseIterable {
    case spotify = "com.spotify.client"
    case appleMusic = "com.apple.Music"

    var appName: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Music"
        }
    }

    var trackInfoSource: String {
        """
        tell application "\(appName)"
            if player state is playing or player state is paused then
                set t to name of current track
                set a to artist of current track
                set al to album of current track
                set s to player state is playing
                return t & "\n" & a & "\n" & al & "\n" & s
            end if
        end tell
        """
    }

    var artworkSource: String {
        switch self {
        case .spotify:
            return """
            tell application "Spotify"
                return artwork url of current track
            end tell
            """
        case .appleMusic:
            return """
            tell application "Music"
                try
                    set artData to raw data of artwork 1 of current track
                    return artData
                end try
            end tell
            """
        }
    }
}

// MARK: - NowPlayingService

@MainActor
final class NowPlayingService: ObservableObject {

    @Published private(set) var nowPlaying: NowPlayingInfo = .empty

    private var mrSendCommand: MRMediaRemoteSendCommandFunction?
    private var mrGetNowPlayingPID: MRMediaRemoteGetNowPlayingApplicationPIDFunction?

    private nonisolated(unsafe) var pollTimer: Timer?

    private var activeMediaApp: MediaApp?
    private var compiledTrackScript: NSAppleScript?
    private var compiledArtworkScript: NSAppleScript?

    private var cachedArtworkURL: String = ""
    private var cachedArtworkImage: NSImage?

    /// Tracks the last title we fetched artwork for to avoid redundant fetches.
    private var lastArtworkTitle: String = ""

    init() {
        loadMRMediaRemote()
        detectAndCompileScripts()
        startPolling()
        fetchNowPlaying()
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - MRMediaRemote

    private func loadMRMediaRemote() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework"
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, URL(fileURLWithPath: path) as CFURL) else { return }

        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
            mrSendCommand = unsafeBitCast(ptr, to: MRMediaRemoteSendCommandFunction.self)
        }
        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationPID" as CFString) {
            mrGetNowPlayingPID = unsafeBitCast(ptr, to: MRMediaRemoteGetNowPlayingApplicationPIDFunction.self)
        }
    }

    // MARK: - Script Compilation

    private func detectAndCompileScripts() {
        let workspace = NSWorkspace.shared
        for app in MediaApp.allCases {
            if workspace.runningApplications.contains(where: { $0.bundleIdentifier == app.rawValue }) {
                activeMediaApp = app
                compiledTrackScript = NSAppleScript(source: app.trackInfoSource)
                compiledTrackScript?.compileAndReturnError(nil)
                compiledArtworkScript = NSAppleScript(source: app.artworkSource)
                compiledArtworkScript?.compileAndReturnError(nil)
                return
            }
        }
        activeMediaApp = nil
        compiledTrackScript = nil
        compiledArtworkScript = nil
    }

    // MARK: - Polling (0.5s)

    private func startPolling() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchNowPlaying()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    // MARK: - Playback Commands

    func togglePlayPause() {
        _ = mrSendCommand?(2, nil)
        // Optimistic: flip instantly
        let c = nowPlaying
        nowPlaying = NowPlayingInfo(title: c.title, artist: c.artist, album: c.album, artwork: c.artwork, isPlaying: !c.isPlaying)
        scheduleRefresh()
    }

    func nextTrack() {
        _ = mrSendCommand?(4, nil)
        scheduleRefresh()
    }

    func previousTrack() {
        _ = mrSendCommand?(5, nil)
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        // 100ms is enough for Spotify/Music to register the command
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.fetchNowPlaying()
        }
    }

    func getNowPlayingAppPID(completion: @escaping (Int32) -> Void) {
        mrGetNowPlayingPID?(DispatchQueue.main, completion)
    }

    // MARK: - Fetch Now Playing (synchronous on main — ~5ms)

    func fetchNowPlaying() {
        if activeMediaApp == nil || compiledTrackScript == nil {
            detectAndCompileScripts()
        }

        guard let _ = activeMediaApp, let trackScript = compiledTrackScript else {
            if nowPlaying != .empty { nowPlaying = .empty }
            return
        }

        // Execute compiled script directly on main thread (~5ms)
        var error: NSDictionary?
        let result: NSAppleEventDescriptor? = trackScript.executeAndReturnError(&error)
        let raw = result?.stringValue ?? ""

        if error != nil && raw.isEmpty {
            // Media app may have quit — re-detect next cycle
            detectAndCompileScripts()
            return
        }

        let lines = raw.components(separatedBy: "\n")
        let title = lines.count > 0 ? lines[0] : ""
        let artist = lines.count > 1 ? lines[1] : ""
        let album = lines.count > 2 ? lines[2] : ""
        let isPlaying = lines.count > 3 && lines[3].contains("true")

        let trackChanged = title != nowPlaying.title || artist != nowPlaying.artist
        let stateChanged = isPlaying != nowPlaying.isPlaying || album != nowPlaying.album

        if trackChanged || stateChanged {
            // Update immediately with existing artwork (or nil if track changed)
            nowPlaying = NowPlayingInfo(
                title: title,
                artist: artist,
                album: album,
                artwork: trackChanged ? nil : nowPlaying.artwork,
                isPlaying: isPlaying
            )
        }

        // Fetch artwork async if track changed (doesn't block UI)
        if trackChanged && !title.isEmpty && activeMediaApp == .spotify {
            fetchArtworkAsync(forTitle: title)
        }
    }

    // MARK: - Artwork (async, decoupled from info)

    private func fetchArtworkAsync(forTitle title: String) {
        guard let artScript = compiledArtworkScript else { return }
        lastArtworkTitle = title

        Task.detached { [weak self] in
            var err: NSDictionary?
            let result: NSAppleEventDescriptor? = artScript.executeAndReturnError(&err)
            let url = result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !url.isEmpty else { return }
            let image = await self?.fetchSpotifyArtwork(url: url)

            await MainActor.run { [weak self] in
                guard let self, self.lastArtworkTitle == title, let image else { return }
                let c = self.nowPlaying
                // Only update if we're still on the same track
                if c.title == title {
                    self.nowPlaying = NowPlayingInfo(
                        title: c.title, artist: c.artist, album: c.album,
                        artwork: image, isPlaying: c.isPlaying
                    )
                }
            }
        }
    }

    private func fetchSpotifyArtwork(url: String) async -> NSImage? {
        if url == cachedArtworkURL, let cached = cachedArtworkImage {
            return cached
        }
        guard let artURL = URL(string: url) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: artURL)
            let image = NSImage(data: data)
            await MainActor.run { [weak self] in
                self?.cachedArtworkURL = url
                self?.cachedArtworkImage = image
            }
            return image
        } catch {
            return nil
        }
    }
}
