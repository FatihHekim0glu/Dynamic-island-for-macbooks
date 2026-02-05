// NowPlayingService.swift
// MacIsland
//
// Reads now-playing state and sends playback commands to the active media app.
//
// On modern macOS (Sequoia+), MRMediaRemote read APIs are broken:
//   - GetNowPlayingInfo returns empty ("Operation not permitted")
//   - GetNowPlayingApplicationIsPlaying returns incorrect values
// So we use AppleScript for ALL reads (track info + playback state)
// and MRMediaRemoteSendCommand for writes (play/pause/next/prev).

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

    var trackInfoScript: String {
        """
        tell application "\(appName)"
            if player state is playing or player state is paused then
                set t to name of current track
                set a to artist of current track
                set al to album of current track
                set s to player state is playing
                return t & "\\n" & a & "\\n" & al & "\\n" & s
            end if
        end tell
        """
    }

    var artworkScript: String {
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

    // MRMediaRemote — only used for sending commands
    private var mrSendCommand: MRMediaRemoteSendCommandFunction?
    private var mrGetNowPlayingPID: MRMediaRemoteGetNowPlayingApplicationPIDFunction?

    private nonisolated(unsafe) var pollTimer: Timer?

    /// The detected running media app.
    private var activeMediaApp: MediaApp?

    /// Cached Spotify artwork URL to avoid re-downloading.
    private var cachedArtworkURL: String = ""
    private var cachedArtworkImage: NSImage?

    /// Flag to avoid overlapping AppleScript queries.
    private var isFetching: Bool = false

    init() {
        loadMRMediaRemote()
        detectActiveMediaApp()
        startPolling()
        fetchNowPlaying()
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - MRMediaRemote (Commands Only)

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

    // MARK: - Polling

    private func startPolling() {
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
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
        scheduleRefresh(delay: 0.3)
    }

    func nextTrack() {
        _ = mrSendCommand?(4, nil)
        scheduleRefresh(delay: 0.5)
    }

    func previousTrack() {
        _ = mrSendCommand?(5, nil)
        scheduleRefresh(delay: 0.5)
    }

    private func scheduleRefresh(delay: Double) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self?.fetchNowPlaying()
        }
    }

    func getNowPlayingAppPID(completion: @escaping (Int32) -> Void) {
        mrGetNowPlayingPID?(DispatchQueue.main, completion)
    }

    // MARK: - Active Media App Detection

    private func detectActiveMediaApp() {
        let workspace = NSWorkspace.shared
        for app in MediaApp.allCases {
            if workspace.runningApplications.contains(where: { $0.bundleIdentifier == app.rawValue }) {
                activeMediaApp = app
                return
            }
        }
        activeMediaApp = nil
    }

    // MARK: - Fetch Now Playing (AppleScript)

    func fetchNowPlaying() {
        // Avoid overlapping fetches (AppleScript takes ~50ms)
        guard !isFetching else { return }
        isFetching = true

        // Re-detect media app periodically in case user launched/quit one
        detectActiveMediaApp()

        guard let app = activeMediaApp else {
            isFetching = false
            if nowPlaying != .empty {
                nowPlaying = .empty
            }
            return
        }

        // Run AppleScript off the main thread via Process/osascript
        let script = app.trackInfoScript
        let artScript = app == .spotify ? app.artworkScript : nil

        Task.detached { [weak self] in
            // Get track info + playing state in one call
            let trackResult = Self.runOsascript(script)
            let lines = trackResult?.components(separatedBy: "\n") ?? []

            let title = lines.count > 0 ? lines[0].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let artist = lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let album = lines.count > 2 ? lines[2].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let playingStr = lines.count > 3 ? lines[3].trimmingCharacters(in: .whitespacesAndNewlines) : "false"
            let isPlaying = playingStr == "true"

            // Fetch artwork
            var artwork: NSImage? = nil
            if let artScript = artScript, !title.isEmpty {
                let artResult = Self.runOsascript(artScript)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !artResult.isEmpty, app == .spotify {
                    artwork = await self?.fetchSpotifyArtwork(url: artResult)
                }
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isFetching = false

                let newInfo = NowPlayingInfo(
                    title: title,
                    artist: artist,
                    album: album,
                    artwork: artwork ?? self.nowPlaying.artwork,
                    isPlaying: isPlaying
                )

                if self.nowPlaying != newInfo || (artwork != nil && artwork !== self.nowPlaying.artwork) {
                    self.nowPlaying = newInfo
                }
            }
        }
    }

    // MARK: - osascript via Process

    /// Runs an AppleScript string via /usr/bin/osascript. Thread-safe.
    private nonisolated static func runOsascript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // Suppress errors

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Spotify Artwork

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
