import Foundation
import OSLog

struct QQMusicTrackMatch: Codable, Hashable, Sendable {
    let id: Int64
    let title: String
    let album: String
    let artist: String
    let durationSeconds: Int
}

actor QQMusicLyricMatchStore {
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MeloX",
        category: "QQMusicLyricMatch"
    )

    private let fileURL: URL
    private var matches: [String: QQMusicTrackMatch]?

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let defaultURL = Self.defaultFileURL
            Self.migrateLegacyFileIfNeeded(to: defaultURL)
            self.fileURL = defaultURL
        }
    }

    func match(for neteaseSongID: Int) -> QQMusicTrackMatch? {
        loadIfNeeded()
        return matches?[String(neteaseSongID)]
    }

    func set(_ match: QQMusicTrackMatch, for neteaseSongID: Int) {
        loadIfNeeded()
        matches?[String(neteaseSongID)] = match
        persist()
    }

    func remove(for neteaseSongID: Int) {
        loadIfNeeded()
        matches?[String(neteaseSongID)] = nil
        persist()
    }

    private func loadIfNeeded() {
        guard matches == nil else { return }
        guard FileManager.default.fileExists(
            atPath: fileURL.path
        ) else {
            matches = [:]
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            matches = try JSONDecoder().decode(
                [String: QQMusicTrackMatch].self,
                from: data
            )
        } catch {
            Self.logger.error(
                "Failed to load QQ lyric matches: \(error.localizedDescription, privacy: .public)"
            )
            matches = [:]
        }
    }

    private func persist() {
        guard let matches else {
            return
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(matches)
        } catch {
            Self.logger.error(
                "Failed to encode QQ lyric matches: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error(
                "Failed to persist QQ lyric matches: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static var defaultFileURL: URL {
        AppStorageLocations.applicationSupportRoot()
            .appendingPathComponent("Lyrics", isDirectory: true)
            .appendingPathComponent(
                "qq-matches.json",
                isDirectory: false
            )
    }

    nonisolated private static var legacyFileURL: URL {
        let root = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("MeloX", isDirectory: true)
            .appendingPathComponent("Lyrics", isDirectory: true)
            .appendingPathComponent("qq-matches.json")
    }

    nonisolated private static func migrateLegacyFileIfNeeded(
        to destinationURL: URL
    ) {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(
            atPath: destinationURL.path
        ) else {
            return
        }
        let legacyURL = legacyFileURL
        guard fileManager.fileExists(
            atPath: legacyURL.path
        ) else {
            return
        }
        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(
                at: legacyURL,
                to: destinationURL
            )
        } catch {
            Self.logger.error(
                "Failed to migrate QQ lyric matches: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
