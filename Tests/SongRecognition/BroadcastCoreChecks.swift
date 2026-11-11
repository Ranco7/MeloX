// Portable production-core checks. No device, entitlements, network or Apple SDK.
import Foundation

@main
struct BroadcastCoreChecks {
    static let binding = BroadcastBinding(extensionID: "fixture.BroadcastUpload", groupID: "group.fixture.MeloX")
    static func main() throws {
        try pcmChecks()
        resamplingChecks()
        try sessionChecks()
        try mailboxChecks()
    }

    static func pcmChecks() throws {
        for bigEndian in [false, true] {
            for interleaved in [false, true] {
                let channels: [[Int16]] = [[16_384, -32_768, 0], [0, 0, 16_384]]
                func bytes(_ values: [Int16]) -> Data {
                    Data(values.flatMap { value -> [UInt8] in
                        let bits = UInt16(bitPattern: value)
                        let lo = UInt8(truncatingIfNeeded: bits), hi = UInt8(truncatingIfNeeded: bits >> 8)
                        return bigEndian ? [hi, lo] : [lo, hi]
                    })
                }
                let planes = interleaved ? [bytes((0..<3).flatMap { [channels[0][$0], channels[1][$0]] })] : channels.map(bytes)
                let format = BroadcastPCMFormat(rate: 48_000, channels: 2, bits: 16,
                    bytesPerFrame: interleaved ? 4 : 2, interleaved: interleaved, bigEndian: bigEndian, encoding: .signedInteger)
                let mono = try BroadcastPCMDecoder.mono(planes: planes, frames: 3, format: format)
                precondition(mono == [0.25, -0.5, 0.25])
            }
        }
        // ASBD 0xe is packed signed big-endian Int16, not native-endian Float32.
        let be = BroadcastPCMFormat(rate: 44_100, channels: 1, bits: 16, bytesPerFrame: 2,
                                    interleaved: true, bigEndian: true, encoding: .signedInteger)
        let decodedBE = try BroadcastPCMDecoder.mono(planes: [Data([0x40, 0, 0xc0, 0])], frames: 2, format: be)
        precondition(decodedBE == [0.5, -0.5])
        for bits in [24, 32] {
            let bytes = bits / 8
            for bigEndian in [false, true] {
                let words: [UInt32] = [1 << (bits - 2), 1 << (bits - 1)]
                let data = Data(words.flatMap { word in (0..<bytes).map { UInt8(truncatingIfNeeded: word >> ((bigEndian ? bytes - 1 - $0 : $0) * 8)) } })
                let format = BroadcastPCMFormat(rate: 48_000, channels: 1, bits: bits, bytesPerFrame: bytes,
                    interleaved: true, bigEndian: bigEndian, encoding: .signedInteger)
                let values = try BroadcastPCMDecoder.mono(planes: [data], frames: 2, format: format)
                precondition(values == [0.5, -1])
            }
        }
        for bits in [32, 64] {
            for bigEndian in [false, true] {
                let bytes = bits / 8
                let words: [UInt64] = bits == 32 ? [UInt64(Float(0.75).bitPattern), UInt64(Float.nan.bitPattern)] : [Double(0.75).bitPattern, Double.nan.bitPattern]
                let data = Data(words.flatMap { word in (0..<bytes).map { UInt8(truncatingIfNeeded: word >> ((bigEndian ? bytes - 1 - $0 : $0) * 8)) } })
                let format = BroadcastPCMFormat(rate: 48_000, channels: 1, bits: bits, bytesPerFrame: bytes,
                                                interleaved: false, bigEndian: bigEndian, encoding: .float)
                let values = try BroadcastPCMDecoder.mono(planes: [data], frames: 2, format: format)
                precondition(values == [0.75, 0])
            }
        }
        do {
            _ = try BroadcastPCMDecoder.mono(planes: [Data([0])], frames: 2, format: be)
            fatalError("Truncated PCM accepted")
        } catch BroadcastCoreError.invalidPCM { }
        print("PASS: real LE/BE integer and float PCM, planar/interleaved stereo, non-finite and truncated input")
    }

    static func resamplingChecks() {
        for rate in [44_100.0, 48_000.0] {
            let input = (0..<Int(rate)).map { Float(0.5 * sin(2 * .pi * 440 * Double($0) / rate)) }
            var whole = BroadcastResampler(inputRate: rate)
            let expected = whole.append(input)
            var chunks = BroadcastResampler(inputRate: rate)
            var actual: [Float] = []
            for start in stride(from: 0, to: input.count, by: 317) {
                actual += chunks.append(Array(input[start..<min(start + 317, input.count)]))
            }
            precondition(actual == expected, "Resampling must span callback boundaries")
            precondition(abs(actual.count - 8_000) <= 1)
            let rms = sqrt(actual.dropFirst(100).reduce(0.0) { $0 + Double($1 * $1) } / Double(actual.count - 100))
            precondition((0.33...0.38).contains(rms), "Audible band changed unexpectedly")
            var ring = BroadcastRing(capacity: 800)
            ring.append(Array(actual.prefix(600)))
            ring.append(Array(actual.dropFirst(600)))
            precondition(ring.samples == Array(actual.suffix(800)) && ring.count == 800 && ring.hasSound)
        }
        let quiet = BroadcastRing(capacity: 80)
        precondition(!quiet.hasSound)
        print("PASS: 44.1/48 kHz streaming resampling, exact chunk continuity, bounded contiguous ring and silence")
    }

    static func sessionChecks() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let request = BroadcastRequest(duration: 3, binding: binding, now: now)
        func session() throws -> BroadcastSession {
            try BroadcastSession(request: request, now: now, uptime: 0,
                initialState: BroadcastState(id: request.id, binding: request.binding, phase: .waiting), control: nil)
        }
        var capture = try session()
        capture.append(Array(repeating: 0, count: 8_000), uptime: 1)
        precondition(capture.ring.count == 0, "Wait for music before spending the short capture window")
        capture.append(Array(repeating: 0.5, count: 8_000), uptime: 2)
        capture.pause()
        precondition(capture.ring.count == 0 && capture.phase == .paused)
        capture.resume(uptime: 3)
        capture.append(Array(repeating: 0.25, count: 30_000), uptime: 3)
        precondition(capture.phase == .completed && capture.ring.count == 24_000)
        let snapshot = try capture.state().samples()
        precondition(snapshot == Array(repeating: 0.25, count: 24_000))
        do {
            _ = try BroadcastSession(request: request, now: request.startBefore, uptime: 0,
                initialState: BroadcastState(id: request.id, binding: request.binding, phase: .waiting), control: nil)
            fatalError("An expired picker request started unattended")
        } catch BroadcastCoreError.invalidSession { }
        for command in [BroadcastStop.cancel, .complete, .matched] {
            var capture = try session()
            capture.append(Array(repeating: 0.5, count: 8_000), uptime: 1)
            capture.tick(uptime: 2, control: BroadcastControl(id: UUID(), command: .cancel, binding: request.binding), current: request)
            precondition(capture.phase == .capturing, "Stale controls cannot affect this session")
            capture.tick(uptime: 2, control: BroadcastControl(id: request.id, command: command, binding: request.binding), current: request)
            precondition(capture.phase == (command == .cancel ? .cancelled : .completed))
            if command == .cancel { precondition(capture.state().pcm.isEmpty) }
        }
        var noBuffers = try session()
        noBuffers.tick(uptime: 12, control: nil, current: request)
        precondition(noBuffers.phase == .noAudio)
        var silence = try session()
        silence.append(Array(repeating: 0, count: 8_000), uptime: 1)
        silence.tick(uptime: 12, control: nil, current: request)
        precondition(silence.phase == .silent)
        var paused = try session()
        paused.pause()
        paused.tick(uptime: 18, control: nil, current: request)
        precondition(paused.phase.terminal, "Deadline must work without host runtime or incoming samples")
        var resumed = try session()
        resumed.append(Array(repeating: 0.5, count: 8_000), uptime: 1)
        resumed.pause()
        resumed.resume(uptime: 13)
        resumed.tick(uptime: 13, control: nil, current: request)
        precondition(resumed.phase == .capturing, "Resume needs a fresh no-audio deadline")
        resumed.tick(uptime: 18, control: nil, current: request)
        precondition(resumed.phase.terminal, "Resume must not extend the independent total deadline")
        var stale = try session()
        stale.tick(uptime: 1, control: nil, current: BroadcastRequest(duration: 3, binding: binding))
        precondition(stale.phase == .cancelled)
        var broken = try session()
        broken.fail(.formatError)
        precondition(broken.state().pcm.isEmpty && broken.phase == .formatError)
        do {
            _ = try BroadcastSession(request: request, now: now, uptime: 0,
                initialState: capture.state(), control: nil)
            fatalError("Consumed session started twice")
        } catch BroadcastCoreError.invalidSession { }
        do {
            _ = try BroadcastSession(request: request, now: now, uptime: 0,
                initialState: BroadcastState(id: request.id, binding: request.binding, phase: .waiting),
                control: BroadcastControl(id: request.id, command: .cancel, binding: request.binding))
            fatalError("Cancelled picker request started")
        } catch BroadcastCoreError.invalidSession { }
        print("PASS: bounded capture, pause/resume, deadline, no buffers/silence, manual/match/cancel, stale control and expired/consumed start")
    }

    static func mailboxChecks() throws {
        do { _ = try BroadcastMailbox(container: nil); fatalError("Missing group accepted") }
        catch BroadcastCoreError.unavailable { }
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".broadcast-core-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = try BroadcastMailbox(container: directory)
        let first = try mailbox.prepare(duration: 9, binding: binding)
        try mailbox.publish(BroadcastState(id: first.id, binding: first.binding, phase: .completed, samples: Array(repeating: 0.5, count: 72_000)))
        let firstState = try mailbox.state(first.id)
        precondition(firstState?.frameCount == 72_000)
        let second = try mailbox.prepare(duration: 3, binding: binding)
        try mailbox.send(.cancel, id: first.id, binding: first.binding)
        let currentControl = try mailbox.control(second.id)
        precondition(currentControl == nil)
        try mailbox.publish(BroadcastState(id: first.id, binding: first.binding, phase: .cancelled))
        let secondState = try mailbox.state(second.id)
        precondition(secondState?.phase == .waiting, "Old writer cannot replace the new snapshot")
        for _ in 0..<5 { _ = try mailbox.prepare(duration: 6, binding: binding) }
        let files = try FileManager.default.contentsOfDirectory(at: mailbox.root, includingPropertiesForKeys: nil)
        precondition(files.filter { UUID(uuidString: $0.lastPathComponent) != nil }.count <= 2)
        try Data([0xff]).write(to: mailbox.root.appendingPathComponent("request.plist"), options: .atomic)
        let recovered = try mailbox.prepare(duration: 3, binding: binding)
        let recoveredState = try mailbox.state(recovered.id)
        precondition(recoveredState?.phase == .waiting)
        print("PASS: missing group fallback, durable atomic envelopes, stale writer isolation, bounded disk and corrupt-header recovery")
    }
}
