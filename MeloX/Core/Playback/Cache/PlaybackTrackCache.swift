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
    /// Free space left untouched after a transfer. The cache is disposable,
    /// so it must never be the reason the device runs out of storage.
    nonisolated static let minimumFreeDiskBytes: Int64 =
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

    /// Only one whole-track transfer may run at a time. Two competing
    /// downloads for a seek handoff and a song change would otherwise double
    /// the temporary disk usage.
    private var activeSongID: Int?

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
              !Self.isStreamingPlaylistURL(source.url) else {
            return
        }

        // Only one full-track transfer runs at a time. After a song change the
        // cancelled transfer may still be unwinding; wait for it instead of
        // dropping the new song's request.
        while activeSongID != nil {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !Task.isCancelled,
              cachedFileURL(for: songID, quality: source.quality) == nil else {
            return
        }

        // The directory has to exist before its volume can report free space.
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        guard hasDiskHeadroom() else {
            Self.logger.debug(
                "Skipping track cache for \(songID, privacy: .public): low disk space"
            )
            return
        }

        activeSongID = songID
        defer { activeSongID = nil }

        let temporaryURL = fileManager.temporaryDirectory.appending(
            path: "MeloXPlaybackCache-\(UUID().uuidString).part",
            directoryHint: .notDirectory
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        do {
            let response = try await Self.download(
                from: source.url,
                to: temporaryURL,
                maximumBytes: Self.maximumTrackBytes
            )
            guard !Task.isCancelled else { return }
            guard response.statusCode == 200 else { return }
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

    private func hasDiskHeadroom() -> Bool {
        let values = try? directory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let available =
            values?.volumeAvailableCapacityForImportantUsage else {
            // If the volume cannot report free space, rely on write errors.
            return true
        }
        return available
            >= Self.maximumTrackBytes + Self.minimumFreeDiskBytes
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

    private nonisolated static func download(
        from url: URL,
        to destinationURL: URL,
        maximumBytes: Int64
    ) async throws -> HTTPURLResponse {
        let transfer = BoundedTrackTransfer(
            destinationURL: destinationURL,
            maximumBytes: maximumBytes
        )
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                transfer.start(url: url, continuation: continuation)
            }
        } onCancel: {
            transfer.cancel()
        }
    }

    private nonisolated static func qualityKey(
        _ quality: MusicQuality?
    ) -> String {
        quality?.rawValue ?? "unknown"
    }

    fileprivate nonisolated static func isRejectedMIMEType(
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
        // ADTS AAC also starts with an 0xFFF sync word, but its layer bits are
        // 00; MPEG audio layers use non-zero layer bits.
        if bytes.count >= 2,
           bytes[0] == 0xFF,
           (bytes[1] & 0xF6) == 0xF0 {
            return "aac"
        }
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

/// Streams a response into a file and stops the task as soon as the running
/// byte count or the declared Content-Length exceeds the cache limit. The
/// system `download` convenience API has no per-chunk hook, so an oversized
/// response would already be on disk before the caller could validate it.
private nonisolated final class BoundedTrackTransfer: NSObject,
    URLSessionDataDelegate, @unchecked Sendable {
    private enum TransferError: LocalizedError {
        case invalidResponse
        case rejectedResponse
        case tooLarge
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "The server returned an unusable response."
            case .rejectedResponse:
                "The response is not cacheable audio."
            case .tooLarge:
                "The track exceeds the cache size limit."
            case .writeFailed:
                "The temporary file could not be written."
            }
        }
    }

    private let destinationURL: URL
    private let maximumBytes: Int64
    private let lock = NSLock()

    private var continuation:
        CheckedContinuation<HTTPURLResponse, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var fileHandle: FileHandle?
    private var response: HTTPURLResponse?
    private var receivedBytes: Int64 = 0
    private var finished = false
    private var cancelled = false

    init(destinationURL: URL, maximumBytes: Int64) {
        self.destinationURL = destinationURL
        self.maximumBytes = maximumBytes
    }

    func start(
        url: URL,
        continuation: CheckedContinuation<HTTPURLResponse, Error>
    ) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            continuation.resume(throwing: URLError(.cancelled))
            return
        }
        self.continuation = continuation
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled {
            finish(.failure(URLError(.cancelled)))
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        // The whole file is written by this delegate; letting URLCache keep a
        // second copy would double disk usage.
        configuration.urlCache = nil
        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
        let task = session.dataTask(with: URLRequest(url: url))

        lock.lock()
        self.session = session
        self.task = task
        guard !cancelled, !finished else {
            lock.unlock()
            task.cancel()
            finish(.failure(URLError(.cancelled)))
            return
        }
        // Resuming while holding the lock orders this against cancel(): it
        // either latches before this point or cancels the running task, so the
        // continuation is completed exactly once on both paths.
        task.resume()
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler:
            @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            completionHandler(.cancel)
            finish(.failure(TransferError.invalidResponse))
            return
        }
        if let mimeType = httpResponse.mimeType?.lowercased(),
           PlaybackTrackCache.isRejectedMIMEType(mimeType) {
            completionHandler(.cancel)
            finish(.failure(TransferError.rejectedResponse))
            return
        }
        if httpResponse.expectedContentLength > maximumBytes {
            completionHandler(.cancel)
            finish(.failure(TransferError.tooLarge))
            return
        }

        try? FileManager.default.removeItem(at: destinationURL)
        guard FileManager.default.createFile(
            atPath: destinationURL.path,
            contents: nil
        ) else {
            completionHandler(.cancel)
            finish(.failure(TransferError.writeFailed))
            return
        }
        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: destinationURL)
        } catch {
            completionHandler(.cancel)
            finish(.failure(TransferError.writeFailed))
            return
        }
        lock.lock()
        guard !finished, !cancelled else {
            lock.unlock()
            try? handle.close()
            completionHandler(.cancel)
            finish(.failure(URLError(.cancelled)))
            return
        }
        fileHandle = handle
        self.response = httpResponse
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        guard !finished, !cancelled, let handle = fileHandle else {
            let wasCancelled = cancelled
            lock.unlock()
            dataTask.cancel()
            finish(
                .failure(
                    wasCancelled
                        ? URLError(.cancelled)
                        : TransferError.writeFailed
                )
            )
            return
        }
        guard receivedBytes + Int64(data.count) <= maximumBytes else {
            lock.unlock()
            dataTask.cancel()
            finish(.failure(TransferError.tooLarge))
            return
        }
        do {
            // Keep the write under the lock so `finish` cannot close the
            // handle halfway through a chunk.
            try handle.write(contentsOf: data)
            receivedBytes += Int64(data.count)
            lock.unlock()
        } catch {
            lock.unlock()
            dataTask.cancel()
            finish(.failure(TransferError.writeFailed))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(.failure(error))
            return
        }
        lock.lock()
        let response = self.response
        let byteCount = receivedBytes
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled {
            finish(.failure(URLError(.cancelled)))
            return
        }
        guard let response, byteCount > 0 else {
            finish(.failure(TransferError.invalidResponse))
            return
        }
        finish(.success(response))
    }

    private func finish(_ result: Result<HTTPURLResponse, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let handle = fileHandle
        fileHandle = nil
        let session = self.session
        self.session = nil
        self.task = nil
        lock.unlock()

        try? handle?.close()
        continuation?.resume(with: result)
        session?.finishTasksAndInvalidate()
    }
}
