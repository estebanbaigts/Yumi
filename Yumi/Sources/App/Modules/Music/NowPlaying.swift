import Foundation

/// The apps Yumi can follow. Music and Spotify announce their track changes to the whole
/// system; Deezer, YouTube Music and the video sites are read from the title of their window
/// (the app, or a browser tab on top), and are driven with the Mac's media keys.
enum MusicPlayer: String, CaseIterable, Sendable {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"
    case deezer = "com.deezer.deezer-desktop"
    /// The web player or its installed app: not one bundle, so a name of our own.
    case youtubeMusic = "music.youtube.com"
    /// Sites only played in a browser, named by their address.
    case youtube = "youtube.com"
    case soundcloud = "soundcloud.com"
    case twitch = "twitch.tv"
    case vimeo = "vimeo.com"
    /// Any other page of a browser that sends sound (a web radio): its window title, its browser's name.
    case web = "web"

    var name: String {
        switch self {
        case .music:        return "Musique"
        case .spotify:      return "Spotify"
        case .deezer:       return "Deezer"
        case .youtubeMusic: return "YouTube Music"
        case .youtube:      return "YouTube"
        case .soundcloud:   return "SoundCloud"
        case .twitch:       return "Twitch"
        case .vimeo:        return "Vimeo"
        case .web:          return "Web"
        }
    }

    /// Answers AppleScript and posts its playback changes.
    var isScriptable: Bool { self == .music || self == .spotify }

    /// Name of the distributed notification the app posts when its playback changes.
    var notificationName: String? {
        switch self {
        case .music:   return "com.apple.Music.playerInfo"
        case .spotify: return "com.spotify.client.PlaybackStateChanged"
        default:       return nil
        }
    }

    /// Where it lives on the web, to open it when it is not running.
    var webURL: URL? {
        switch self {
        case .deezer:       return URL(string: "https://www.deezer.com")
        case .youtubeMusic: return URL(string: "https://music.youtube.com")
        case .youtube:      return URL(string: "https://www.youtube.com")
        case .soundcloud:   return URL(string: "https://soundcloud.com")
        case .twitch:       return URL(string: "https://www.twitch.tv")
        case .vimeo:        return URL(string: "https://vimeo.com")
        case .music, .spotify, .web: return nil
        }
    }
}

/// The track a window title shows, for the players that only say it there.
enum MusicTitles {
    /// The browsers and their window suffixes, removed before reading.
    static let browserSuffixes = [" - Google Chrome", " - Microsoft Edge", " - Brave", " — Mozilla Firefox", " - Mozilla Firefox",
                                  " - Arc", " - Safari", " — Safari", " - Opera", " - Vivaldi"]

    /// Pages of a site that are not a track: its home, its lists.
    private static let notTracks: Set<String> = ["home", "accueil", "explore", "explorer", "library", "bibliothèque",
                                                 "subscriptions", "abonnements", "history", "historique", "following", "suivis"]

    /// "Lueur - Halo Nord - YouTube Music" → YouTube Music, "Lueur", "Halo Nord". nil when the
    /// title is not a track of a known player (or only the player's own name, nothing playing).
    static func parse(_ windowTitle: String, appName: String = "") -> (player: MusicPlayer, title: String, artist: String)? {
        let text = clean(windowTitle)

        // Music players: "title - artist"
        let players: [(MusicPlayer, [String])] = [
            (.youtubeMusic, [" - YouTube Music", " | YouTube Music"]),
            (.deezer, [" - Deezer", " | Deezer", " – Deezer"]),
        ]
        for (player, suffixes) in players {
            let isApp = appName.localizedCaseInsensitiveContains(player.name)
            guard let suffix = suffixes.first(where: { text.hasSuffix($0) }) ?? (isApp ? "" : nil) else { continue }
            guard let track = track(in: text, before: suffix, of: player) else { return nil }
            for separator in [" • ", " · ", " - ", " — ", " – "] {
                let parts = track.components(separatedBy: separator)
                if parts.count >= 2 {
                    return (player, parts[0].trimmingCharacters(in: .whitespaces),
                            parts[1...].joined(separator: separator).trimmingCharacters(in: .whitespaces))
                }
            }
            return (player, track, "")
        }

        // SoundCloud: "Stream Lueur by Halo Nord | Listen online for free on SoundCloud"
        for suffix in [" | Listen online for free on SoundCloud", " | SoundCloud"] where text.hasSuffix(suffix) {
            guard var track = track(in: text, before: suffix, of: .soundcloud) else { return nil }
            if track.hasPrefix("Stream ") { track = String(track.dropFirst("Stream ".count)) }
            if let by = track.range(of: " by ", options: .backwards) {
                return (.soundcloud, String(track[..<by.lowerBound]), String(track[by.upperBound...]))
            }
            return (.soundcloud, track, "")
        }

        // Video sites: the title of a video is kept whole, the order of artist and song is anyone's guess
        let videos: [(MusicPlayer, [String])] = [
            (.youtube, [" - YouTube"]),
            (.twitch, [" - Twitch"]),
            (.vimeo, [" on Vimeo", " | Vimeo"]),
        ]
        for (player, suffixes) in videos {
            guard let suffix = suffixes.first(where: { text.hasSuffix($0) }) else { continue }
            guard let track = track(in: text, before: suffix, of: player) else { return nil }
            return (player, track, "")
        }
        return nil
    }

    /// A window title without its browser's name, the sound mark of its tab and a count of notifications.
    static func clean(_ windowTitle: String) -> String {
        // The browser's name goes first: a tab without a title leaves only " - Google Chrome"
        var text = windowTitle
        while text.last?.isWhitespace == true { text.removeLast() }
        for suffix in browserSuffixes where text.hasSuffix(suffix) { text = String(text.dropLast(suffix.count)) }
        // A tab marked as playing sound
        text = text.replacingOccurrences(of: "🔊", with: "").replacingOccurrences(of: "▶ ", with: "").trimmingCharacters(in: .whitespaces)
        // "(3) Lueur - YouTube": the count of unread notifications
        if let count = text.range(of: #"^\(\d+\+?\) "#, options: .regularExpression) { text.removeSubrange(count) }
        return text
    }

    /// What is left of `text` without `suffix`, unless it is only the player's name or one of its lists.
    private static func track(in text: String, before suffix: String, of player: MusicPlayer) -> String? {
        let track = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        guard !track.isEmpty, track.caseInsensitiveCompare(player.name) != .orderedSame,
              !notTracks.contains(track.lowercased()) else { return nil }
        return track
    }
}

/// Whether a player read from its window title is playing. Its title stays the same in pause, but
/// the system knows which apps send sound to the speakers right now (`AudioActivity`).
enum TitlePlayback {
    /// True when the app `bundleID`, or one of its helper processes, is in `audible` (bundle
    /// identifiers of the processes sending sound, lowercased).
    static func isAudible(_ bundleID: String, among audible: Set<String>) -> Bool {
        var id = bundleID.lowercased()
        // An installed web app plays through Chrome
        if id.hasPrefix("com.google.chrome.app.") { id = "com.google.chrome" }
        let owners: [String]
        switch id {
        // Safari plays through WebKit's processes, shared with the other apps that show web pages
        case "com.apple.safari":    owners = ["com.apple.webkit"]
        case "org.mozilla.firefox": owners = [id, "org.mozilla.plugincontainer"]
        default:                    owners = [id]
        }
        return audible.contains { process in owners.contains { process == $0 || process.hasPrefix($0 + ".") } }
    }

    /// Whether to show a track seen in a window title as playing (true), paused (false), or not at all (nil).
    /// - Parameters:
    ///   - previous: what was shown for this player at the last look.
    ///   - audible: whether its app sends sound now; nil when the system could not say.
    ///   - pressedRecently: a button of the island just played or paused it: trust that over the sound,
    ///     which a browser may keep running for a few seconds after a pause.
    static func isPlaying(title: String, previous: NowPlaying?, audible: Bool?, pressedRecently: Bool = false) -> Bool? {
        let sameTrack = previous?.title == title
        if pressedRecently, sameTrack, let previous { return previous.isPlaying }
        switch audible {
        case true?:
            return true
        case false?:
            // A page never heard is not a track: a video open that nobody started
            return sameTrack ? false : nil
        case nil:
            // Without the sound, the last button pressed decides
            return !(sameTrack && previous?.isPlaying == false)
        }
    }
}

/// A browser that sends sound while none of its windows shows a known site: a web radio, a
/// podcast page. Yumi shows the title of one of its windows, the one in front unless the one
/// already shown is still open, since a title alone does not say which tab plays.
enum BrowserFallback {
    /// Safari plays through WebKit processes shared with Mail and every app showing a web page:
    /// its sound cannot be told apart, so a page that is not a known site is never guessed there.
    static func canTellItsSound(_ bundleID: String) -> Bool {
        bundleID.lowercased() != "com.apple.safari"
    }

    /// The title to show among the browser's window titles, front first; nil when they are all empty.
    static func title(among windowTitles: [String], previous: String?) -> String? {
        let titles = windowTitles.map(MusicTitles.clean).filter { !$0.isEmpty }
        if let previous, titles.contains(previous) { return previous }
        return titles.first
    }

    /// Whether to show the page as playing (true), paused (false), or not at all (nil). Stricter
    /// than a known site: without the sound it is never shown, and a page shows only after its
    /// browser was heard at two looks in a row, so a notification sound is not taken for music.
    /// - Parameters:
    ///   - heardBefore: the browser was already heard at the last look.
    static func isPlaying(title: String, previous: NowPlaying?, audible: Bool?, heardBefore: Bool,
                          pressedRecently: Bool = false) -> Bool? {
        let sameTrack = previous?.title == title
        if pressedRecently, sameTrack, let previous { return previous.isPlaying }
        switch audible {
        case true?:  return previous != nil || heardBefore ? true : nil
        case false?: return sameTrack ? false : nil
        case nil:    return nil
        }
    }
}

struct NowPlaying: Equatable, Sendable {
    var player: MusicPlayer
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    /// Length of the track in seconds, when the player says it.
    var duration: TimeInterval? = nil
    /// Position in the track when this was reported, in seconds. Not every player says it.
    var position: TimeInterval? = nil

    /// True when `other` is the same track, whatever its state.
    func isSameTrack(as other: NowPlaying) -> Bool {
        player == other.player && title == other.title && artist == other.artist && album == other.album
    }
}

/// Where a track is, between two reports of its player: a position and the moment it was true.
struct PlaybackClock: Equatable, Sendable {
    var position: TimeInterval
    var since: Date
    var isRunning: Bool

    func position(at now: Date) -> TimeInterval {
        isRunning ? position + max(0, now.timeIntervalSince(since)) : position
    }

    /// The clock after the player reported `new`. A reported position is taken as it is; a new
    /// track starts at zero; a pause freezes the clock and a resume restarts it. nil when the
    /// position cannot be known (a track found already paused, or nothing playing).
    static func next(_ clock: PlaybackClock?, from old: NowPlaying?, to new: NowPlaying?, now: Date) -> PlaybackClock? {
        guard let new else { return nil }
        if let reported = new.position {
            return PlaybackClock(position: reported, since: now, isRunning: new.isPlaying)
        }
        guard let old, old.isSameTrack(as: new) else {
            return new.isPlaying ? PlaybackClock(position: 0, since: now, isRunning: true) : nil
        }
        guard let clock else { return nil }
        return PlaybackClock(position: clock.position(at: now), since: now, isRunning: new.isPlaying)
    }
}

/// What a player just announced.
enum PlayerUpdate: Equatable, Sendable {
    case track(NowPlaying)
    case stopped(MusicPlayer)
}

enum MusicSummary {
    /// Reads the dictionary a player posts with its notification.
    static func update(from userInfo: [AnyHashable: Any]?, player: MusicPlayer) -> PlayerUpdate {
        let state = (userInfo?["Player State"] as? String ?? "").lowercased()
        guard let title = userInfo?["Name"] as? String, !title.isEmpty, state == "playing" || state == "paused" else {
            return .stopped(player)
        }
        // Music gives "Total Time" and Spotify "Duration", both in milliseconds; only Spotify gives the position.
        let milliseconds = number(userInfo?["Total Time"]) ?? number(userInfo?["Duration"])
        return .track(NowPlaying(player: player, title: title,
                                 artist: userInfo?["Artist"] as? String ?? "",
                                 album: userInfo?["Album"] as? String ?? "",
                                 isPlaying: state == "playing",
                                 duration: milliseconds.flatMap { $0 > 0 ? $0 / 1000 : nil },
                                 position: number(userInfo?["Playback Position"])))
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        // AppleScript writes decimals the way the Mac's region does: "12,5" in French.
        if let text = value as? String { return Double(text.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    /// Reads the answer of the AppleScript query: title, artist, album, state, position in seconds
    /// and duration, separated by tabs. Music gives the duration in seconds, Spotify in milliseconds.
    static func update(fromScriptResult result: String, player: MusicPlayer) -> PlayerUpdate {
        let fields = result.components(separatedBy: "\t")
        guard fields.count >= 4 else { return .stopped(player) }
        var info: [AnyHashable: Any] = ["Name": fields[0], "Artist": fields[1], "Album": fields[2], "Player State": fields[3]]
        if fields.count >= 6 {
            info["Playback Position"] = fields[4]
            if let duration = number(fields[5]) { info["Duration"] = player == .music ? duration * 1000 : duration }
        }
        return update(from: info, player: player)
    }

    /// What is playing after an update. The player that is playing keeps the stage:
    /// another one pausing or stopping in the background does not replace it.
    static func apply(_ update: PlayerUpdate, to current: NowPlaying?) -> NowPlaying? {
        switch update {
        case .track(let track):
            if track.isPlaying { return track }
            if let current, current.isPlaying, current.player != track.player { return current }
            return track
        case .stopped(let player):
            return current?.player == player ? nil : current
        }
    }

    /// How long a paused track stays in the folded island, so it can be resumed from there.
    static let pausedLinger: TimeInterval = 5 * 60

    /// A page that is not a known site may have been any sound: it leaves after a minute.
    static func pausedLinger(for player: MusicPlayer) -> TimeInterval {
        player == .web ? 60 : pausedLinger
    }

    /// What the folded island shows: the track while it plays, and for a few minutes after a pause.
    /// - Parameter pausedFor: seconds since the track was paused, when it is.
    static func live(_ playing: NowPlaying?, canControl: Bool, pausedFor: TimeInterval? = nil) -> ModuleLive? {
        guard let playing else { return nil }
        if !playing.isPlaying {
            guard let pausedFor, pausedFor < pausedLinger(for: playing.player) else { return nil }
        }
        let text = playing.artist.isEmpty ? playing.title : "\(playing.title) · \(playing.artist)"
        let controls = [
            playing.isPlaying
                ? ModuleControl(id: ModuleAction.primary.rawValue, symbol: "pause.fill", label: loc("Pause"))
                : ModuleControl(id: ModuleAction.primary.rawValue, symbol: "play.fill", label: loc("Lecture")),
            ModuleControl(id: ModuleAction.secondary.rawValue, symbol: "forward.fill", label: loc("Suivant")),
        ]
        return ModuleLive(text: text,
                          priority: playing.isPlaying ? ModuleLivePriority.activity : ModuleLivePriority.ambient,
                          controls: canControl ? controls : [])
    }

    /// - Parameters:
    ///   - canControl: false in builds that may not send commands to other apps.
    ///   - pausedFor: seconds since the track was paused, when it is.
    ///   - position: seconds into the track, when it is known.
    static func snapshot(_ playing: NowPlaying?, canControl: Bool, pausedFor: TimeInterval? = nil,
                         position: TimeInterval? = nil) -> ModuleSnapshot {
        var snapshot = plainSnapshot(playing, canControl: canControl, pausedFor: pausedFor).withSymbols("music.note")
        if let duration = playing?.duration, duration > 0, let position {
            let at = min(duration, max(0, position))
            snapshot.progress = ModuleProgress(fraction: at / duration, leading: FrenchText.trackTime(at),
                                               trailing: FrenchText.trackTime(duration))
        }
        return snapshot
    }

    private static func plainSnapshot(_ playing: NowPlaying?, canControl: Bool, pausedFor: TimeInterval?) -> ModuleSnapshot {
        var snapshot = ModuleSnapshot(id: "music", name: loc("Musique"), colorHex: "#F58AD9", status: loc("silence"),
                                      title: loc("Pas de musique."), subtitle: loc("Lance un morceau, j'écoute avec toi."),
                                      primaryAction: loc("Ouvrir Musique"), secondaryAction: nil)
        guard let playing else { return snapshot }

        snapshot.status = playing.isPlaying ? loc("lecture") : loc("pause")
        snapshot.title = playing.title
        snapshot.source = playing.player.name
        let credits = [playing.artist, playing.album].filter { !$0.isEmpty }
        snapshot.subtitle = credits.isEmpty ? playing.player.name : credits.joined(separator: ", ")
        if canControl {
            snapshot.primaryAction = playing.isPlaying ? loc("Pause") : loc("Lecture")
            snapshot.secondaryAction = loc("Suivant")
        } else {
            snapshot.primaryAction = loc("Ouvrir \(playing.player.name)")
        }
        snapshot.live = live(playing, canControl: canControl, pausedFor: pausedFor)
        return snapshot
    }
}
