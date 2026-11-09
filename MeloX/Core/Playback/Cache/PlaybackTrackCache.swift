import Foundation
import OSLog

/// Bounded, purgable cache for the currently playing track.
///
/// Playback itself still starts from the remote stream. Once the track has
/// started, this cache downloads the complete file in the background so later
/// seeks (and a later playback of the same track) can use a local file instead
/// of re-requesting byte ranges from the CDN.
actor PlaybackTrackCache {
    nonisolated static let shared = PlaybackTrackCache()

    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MeloX",
        category: "PlaybackTrackCache"
    )

    nonisolated static let maximumCacheBytes: Int64 =
        512 * 1_024 * 1_024
    nonisolated static let maximumTrackBytes: Int64 =
        128 * 1_024 * 1_024
    nonisolated static let maximumAge: TimeInterval =
        7 * 24 * 60 * 60

    /// Extensions understood by the bundled AudioStreaming file source.
    /// Ogg/APE files are intentionally not cached because that source cannot
    /// open them from disk.
    private nonisolated static let supportedExtensions: Set<String> = [
        "mp3", "flac", "m4a", "mp4", "aac", "ac3",
        "wav", "aifc", "aiff", "caf", "3gp",
    ]

    private let directory: URL
    private let fileManager: FileManager

    init(
        directory: URL = AppStorageLocations.playbackCacheDirectory(),
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.fileManager = fileManager
    }

    nonisolated static func clearCache(
        fileManager: FileManager = .default
    ) {
        try? fileManager.removeItem(
            at: AppStorageLocations.playbackCacheDirectory(
                fileManager: fileManager
            )
        )
    }

    /// Returns a local source only when a complete, validated file for this
    /// song and quality is still present. File metadata is refreshed so the
    /// least recently used track is pruned first.
    func cachedSource(
        for songID: Int,
        metadata: PlaybackSource
    ) -> PlaybackSource? {
        guard let fileURL = cachedFileURL(
            for: songID,
            quality: metadata.quality
        ) else {
            return nil
        }
        try? fileManager.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )
        return PlaybackSource(
            url: fileURL,
            bitrate: metadata.bitrate,
            format: metadata.format,
            quality: metadata.quality
        )
    }

    /// Downloads and installs the complete track. Safe to call while playback
    /// is already running; cancellation leaves no partial file behind.
    func prepare(songID: Int, source: PlaybackSource) async {
        guard source.url.isFileURL == false,
              let scheme = source.url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              !isStreamingPlaylistURL(source.url),
              cachedFileURL(for: songID, quality: source.quality) == nil else {
            return
        }

        do {
            let (temporaryURL, response) = try await URLSession.shared.download(
                from: source.url
            )
            defer { try? fileManager.removeItem(at: temporaryURL) }
            guard !Task.isCancelled else { return }
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return
            }
            if httpResponse.expectedContentLength > Self.maximumTrackBytes {
                return
            }
            if let mimeType = httpResponse.mimeType?.lowercased(),
               Self.isRejectedMIMEType(mimeType) {
                return
            }
            let values = try temporaryURL.resourceValues(
                forKeys: [.fileSizeKey]
            )
            let byteCount = Int64(values.fileSize ?? 0)
            guard byteCount > 0,
                  byteCount <= Self.maximumTrackBytes,
                  let header = try? Self.readHeader(at: temporaryURL),
                  let fileExtension = Self.fileExtension(
                      for: header,
                      source: source
                  ) else {
                return
            }

            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            // A previous quality may still be on disk; it must not be served
            // through this metadata.
            for oldURL in cachedFiles(for: songID) {
                try? fileManager.removeItem(at: oldURL)
            }

            let destination = directory.appending(
                path: "\(songID)_\(Self.qualityKey(source.quality)).\(fileExtension)",
                directoryHint: .notDirectory
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporaryURL, to: destination)
            try? fileManager.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: destination.path
            )
            prune(keeping: destination)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            Self.logger.debug(
                "Track cache download failed for \(songID, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func remove(songID: Int) {
        for url in cachedFiles(for: songID) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func cachedFileURL(
        for songID: Int,
        quality: MusicQuality?
    ) -> URL? {
        let prefix = "\(songID)_\(Self.qualityKey(quality))."
        return cachedFiles(for: songID).first { url in
            guard url.lastPathComponent.hasPrefix(prefix),
                  let values = try? url.resourceValues(
                      forKeys: [
                          .fileSizeKey,
                          .contentModificationDateKey,
                          .isRegularFileKey,
                      ]
                  ),
                  values.isRegularFile == true,
                  (values.fileSize ?? 0) > 0 else {
                return false
            }
            if let modificationDate = values.contentModificationDate,
               Date().timeIntervalSince(modificationDate)
                   > Self.maximumAge {
                try? fileManager.removeItem(at: url)
                return false
            }
            return true
        }
    }

    private func cachedFiles(for songID: Int) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents.filter {
            $0.lastPathComponent.hasPrefix("\(songID)_")
        }
    }

    private func prune(keeping keptURL: URL) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .fileSizeKey,
                .contentModificationDateKey,
                .isRegularFileKey,
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let now = Date()
        var entries: [(url: URL, byteCount: Int64, date: Date)] = []
        for url in contents {
            guard let values = try? url.resourceValues(
                forKeys: [
                    .fileSizeKey,
                    .contentModificationDateKey,
                    .isRegularFileKey,
                ]
            ), values.isRegularFile == true else {
                continue
            }
            let date = values.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(date) > Self.maximumAge {
                try? fileManager.removeItem(at: url)
                continue
            }
            entries.append(
                (
                    url,
                    Int64(values.fileSize ?? 0),
                    date
                )
            )
        }

        var totalBytes = entries.reduce(Int64(0)) {
            $0 + $1.byteCount
        }
        guard totalBytes > Self.maximumCacheBytes else { return }

        entries.sort { $0.date < $1.date }
        for entry in entries
        where totalBytes > Self.maximumCacheBytes {
            guard entry.url != keptURL else { continue }
            try? fileManager.removeItem(at: entry.url)
            totalBytes -= entry.byteCount
        }
    }

    private nonisolated static func qualityKey(
        _ quality: MusicQuality?
    ) -> String {
        quality?.rawValue ?? "unknown"
    }

    private nonisolated static func isRejectedMIMEType(
        _ mimeType: String
    ) -> Bool {
        mimeType.hasPrefix("text/")
            || mimeType == "application/json"
            || mimeType.hasSuffix("+json")
            || mimeType == "application/xml"
            || mimeType.hasSuffix("+xml")
            || mimeType.contains("mpegurl")
            || mimeType.contains("drm")
    }

    private nonisolated static func isStreamingPlaylistURL(
        _ url: URL
    ) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        return fileExtension == "m3u8" || fileExtension == "m3u"
    }

    private nonisolated static func readHeader(
        at url: URL
    ) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: 32) ?? Data()
    }

    /// Picks the extension from the actual payload first. AudioStreaming's
    /// local file source uses the extension as its AudioFileTypeID hint, so a
    /// signed CDN URL without a suffix must still produce a usable file name.
    private nonisolated static func fileExtension(
        for header: Data,
        source: PlaybackSource
    ) -> String? {
        let bytes = [UInt8](header)
        if bytes.starts(with: [0x49, 0x44, 0x33])
            || (
                bytes.count >= 2
                    && bytes[0] == 0xFF
                    && (bytes[1] & 0xE0) == 0xE0
            ) {
            return "mp3"
        }
        if bytes.starts(with: [0x66, 0x4C, 0x61, 0x43]) {
            return "flac"
        }
        if bytes.starts(with: [0x63, 0x61, 0x66, 0x66]) {
            return "caf"
        }
        if bytes.starts(with: [0x46, 0x4F, 0x52, 0x4D]) {
            return "aiff"
        }
        if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) {
            return "wav"
        }
        if bytes.count >= 8,
           bytes[4..<8].elementsEqual(
               [0x66, 0x74, 0x79, 0x70] as [UInt8]
           ) {
            return "m4a"
        }
        if bytes.starts(with: [0x4F, 0x67, 0x67, 0x53]) {
            // AudioStreaming's file source has no Ogg hint.
            return nil
        }

        let sourceExtension = source.url.pathExtension.lowercased()
        if supportedExtensions.contains(sourceExtension) {
            return sourceExtension
        }
        let formatExtension = source.format?.lowercased() ?? ""
        return supportedExtensions.contains(formatExtension)
            ? formatExtension
            : nil
    }
}
