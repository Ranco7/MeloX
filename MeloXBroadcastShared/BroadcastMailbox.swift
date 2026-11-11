import Foundation

/// One host-owned request; at most two bounded session directories. No process
/// holds a shared lock, so a suspended host cannot stall the extension.
nonisolated struct BroadcastMailbox: Sendable {
    let root: URL
    static let maximumFileBytes = 320_000

    init(container: URL?) throws {
        guard let container else { throw BroadcastCoreError.unavailable }
        root = container.appendingPathComponent("RecognitionBroadcast", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func prepare(duration: Int, binding: BroadcastBinding, now: Date = Date()) throws -> BroadcastRequest {
        let request = BroadcastRequest(duration: duration, binding: binding, now: now)
        try prepare(request)
        return request
    }

    func prepare(_ request: BroadcastRequest) throws {
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        // Retain the current writer until the new request invalidates it.
        // A fresh explicit request also recovers a corrupt old mailbox header.
        let previousRequest = try? currentRequest()
        let previousID = previousRequest?.id
        for folder in folders where folder.lastPathComponent != previousID?.uuidString {
            try FileManager.default.removeItem(at: folder)
        }
        try FileManager.default.createDirectory(at: directory(request.id), withIntermediateDirectories: true)
        try write(BroadcastState(id: request.id, binding: request.binding, phase: .waiting, now: request.createdAt), to: file(request.id, "state.plist"))
        try write(request, to: root.appendingPathComponent("request.plist"))
    }

    func currentRequest() throws -> BroadcastRequest? { try read(root.appendingPathComponent("request.plist")) }
    func state(_ id: UUID) throws -> BroadcastState? {
        let value: BroadcastState? = try read(file(id, "state.plist"))
        guard value == nil || value?.id == id else { throw BroadcastDiagnostic(code: .handshakeMismatch) }
        return value
    }
    func control(_ id: UUID) throws -> BroadcastControl? { try read(file(id, "control.plist")) }
    func send(_ command: BroadcastStop, id: UUID, binding: BroadcastBinding) throws {
        if let previous = try control(id) {
            guard previous.id == id, previous.binding == binding else { throw BroadcastDiagnostic(code: .handshakeMismatch) }
            if previous.command == .cancel { return }
        }
        try write(BroadcastControl(id: id, command: command, binding: binding), to: file(id, "control.plist"))
    }
    func publish(_ state: BroadcastState) throws { try write(state, to: file(state.id, "state.plist")) }
    func clearAudio(_ id: UUID) throws {
        guard var state = try state(id) else { return }
        state.pcm = Data()
        state.frameCount = 0
        try publish(state)
    }

    private func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func file(_ id: UUID, _ name: String) -> URL { directory(id).appendingPathComponent(name) }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(value)
        guard data.count <= Self.maximumFileBytes else { throw BroadcastCoreError.mailbox }
        try data.write(to: url, options: .atomic)
        #if os(iOS)
        // Accessible while the host is suspended/phone locks after first unlock.
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                             ofItemAtPath: url.path)
        #endif
    }
    private func read<T: Decodable>(_ url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            data = try file.read(upToCount: Self.maximumFileBytes + 1) ?? Data()
        } catch { throw BroadcastDiagnostic(code: .notWritable) }
        guard data.count <= Self.maximumFileBytes else { throw BroadcastDiagnostic(code: .handshakeMismatch) }
        do { return try PropertyListDecoder().decode(T.self, from: data) }
        catch { throw BroadcastDiagnostic(code: .handshakeMismatch) }
    }
}
