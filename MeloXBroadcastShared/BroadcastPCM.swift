import Foundation

nonisolated enum BroadcastCoreError: Error {
    case unavailable, invalidSession, invalidPCM, mailbox
}

/// Describes the ASBD, including byte order and stride; PTS is never a sample rate.
nonisolated struct BroadcastPCMFormat: Equatable, Sendable {
    enum Encoding: Equatable, Sendable { case float, signedInteger }
    let rate: Double
    let channels: Int
    let bits: Int
    let bytesPerFrame: Int
    let interleaved: Bool
    let bigEndian: Bool
    let encoding: Encoding
}

nonisolated enum BroadcastPCMDecoder {
    static func mono(planes: [Data], frames: Int, format: BroadcastPCMFormat) throws -> [Float] {
        let bytes = format.bits / 8
        guard format.rate.isFinite, (8_000...192_000).contains(format.rate),
              (1...8).contains(format.channels), (1...16_384).contains(frames),
              [16, 24, 32, 64].contains(format.bits),
              (format.encoding != .float || [32, 64].contains(format.bits)),
              (format.encoding != .signedInteger || format.bits <= 32),
              format.bytesPerFrame >= bytes * (format.interleaved ? format.channels : 1),
              planes.count == (format.interleaved ? 1 : format.channels),
              planes.allSatisfy({ $0.count >= frames * format.bytesPerFrame }) else {
            throw BroadcastCoreError.invalidPCM
        }
        let integerScale = pow(2, Double(format.bits - 1))
        var output = [Float](repeating: 0, count: frames)
        for channel in 0..<format.channels {
            let data = planes[format.interleaved ? 0 : channel]
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                for frame in 0..<frames {
                    let offset = frame * format.bytesPerFrame + (format.interleaved ? channel * bytes : 0)
                    var word: UInt64 = 0
                    for byte in 0..<bytes {
                        let shift = (format.bigEndian ? bytes - 1 - byte : byte) * 8
                        word |= UInt64(raw[offset + byte]) << shift
                    }
                    let value: Double
                    if format.encoding == .float {
                        value = format.bits == 32 ? Double(Float(bitPattern: UInt32(word))) : Double(bitPattern: word)
                    } else {
                        let shift = 64 - format.bits
                        let signed = Int64(bitPattern: word << shift) >> shift
                        value = Double(signed) / integerScale
                    }
                    output[frame] += Float(value.isFinite ? max(-1, min(1, value)) : 0) / Float(format.channels)
                }
            }
        }
        return output
    }
}

/// Streaming low-pass FIR + interpolation. State spans callback boundaries.
/// A rate change or pause starts a fresh contiguous window at the caller.
nonisolated struct BroadcastResampler {
    static let rate = 8_000
    private let inputRate: Double
    private let coefficients: [Double]
    private var history = [Double](repeating: 0, count: 63)
    private var cursor = 0
    private var inputIndex = 0
    private var nextPosition = 0.0
    private var previous = 0.0

    init(inputRate: Double) {
        self.inputRate = inputRate
        let cutoff = min(0.45, 3_600 / inputRate)
        var taps = (0..<63).map { index -> Double in
            let x = Double(index - 31)
            let sinc = x == 0 ? 2 * cutoff : sin(2 * .pi * cutoff * x) / (.pi * x)
            return sinc * (0.54 - 0.46 * cos(2 * .pi * Double(index) / 62))
        }
        let sum = taps.reduce(0, +)
        for index in taps.indices { taps[index] /= sum }
        coefficients = taps
    }

    mutating func append(_ input: [Float]) -> [Float] {
        if inputRate == Double(Self.rate) { return input }
        var output: [Float] = []
        output.reserveCapacity(Int(Double(input.count) * Double(Self.rate) / inputRate) + 1)
        for sample in input {
            history[cursor] = Double(sample)
            var filtered = 0.0
            for tap in coefficients.indices {
                filtered += coefficients[tap] * history[(cursor - tap + 63) % 63]
            }
            cursor = (cursor + 1) % 63
            while nextPosition <= Double(inputIndex) {
                let fraction = max(0, min(1, nextPosition - Double(inputIndex - 1)))
                output.append(Float(previous + (filtered - previous) * fraction))
                nextPosition += inputRate / Double(Self.rate)
            }
            previous = filtered
            inputIndex += 1
        }
        return output
    }
}

nonisolated struct BroadcastRing {
    private var storage: [Float]
    private var cursor = 0
    private(set) var count = 0
    private(set) var total = 0

    init(capacity: Int) { storage = Array(repeating: 0, count: max(1, capacity)) }

    mutating func append(_ samples: [Float]) {
        for sample in samples {
            storage[cursor] = sample
            cursor = (cursor + 1) % storage.count
            count = min(count + 1, storage.count)
            total += 1
        }
    }

    var samples: [Float] {
        let start = count == storage.count ? cursor : 0
        return (0..<count).map { storage[(start + $0) % storage.count] }
    }

    var hasSound: Bool {
        // Ignore numerical noise while retaining quiet music. No volume is changed.
        samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, count)) > 0.00000001
    }
}
