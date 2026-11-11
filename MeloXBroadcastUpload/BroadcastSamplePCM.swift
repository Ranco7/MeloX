import AudioToolbox
import CoreMedia
import Foundation

/// Copies only a bounded audio callback. Never retains a CMSampleBuffer.
nonisolated enum BroadcastSamplePCM {
    static func decode(_ sample: CMSampleBuffer) throws -> (BroadcastPCMFormat, [Float]) {
        guard sample.isValid, (1...16_384).contains(sample.numSamples),
              let description = sample.formatDescription,
              let pointer = CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
            throw BroadcastCoreError.invalidPCM
        }
        let asbd = pointer.pointee
        let flags = asbd.mFormatFlags
        guard asbd.mFormatID == kAudioFormatLinearPCM,
              flags & kAudioFormatFlagIsPacked != 0,
              flags & kAudioFormatFlagIsAlignedHigh == 0,
              (flags & kAudioFormatFlagIsFloat != 0) != (flags & kAudioFormatFlagIsSignedInteger != 0) else {
            throw BroadcastCoreError.invalidPCM
        }
        let format = BroadcastPCMFormat(
            rate: asbd.mSampleRate, channels: Int(asbd.mChannelsPerFrame), bits: Int(asbd.mBitsPerChannel),
            bytesPerFrame: Int(asbd.mBytesPerFrame), interleaved: flags & kAudioFormatFlagIsNonInterleaved == 0,
            bigEndian: flags & kAudioFormatFlagIsBigEndian != 0,
            encoding: flags & kAudioFormatFlagIsFloat != 0 ? .float : .signedInteger)
        let mono = try sample.withAudioBufferList { buffers, _ -> [Float] in
            guard buffers.count == (format.interleaved ? 1 : format.channels), buffers.count <= 8 else {
                throw BroadcastCoreError.invalidPCM
            }
            let planes: [Data] = try buffers.map { buffer in
                guard Int(buffer.mNumberChannels) == (format.interleaved ? format.channels : 1),
                      buffer.mDataByteSize <= 1_048_576, let data = buffer.mData else {
                    throw BroadcastCoreError.invalidPCM
                }
                return Data(bytes: data, count: Int(buffer.mDataByteSize))
            }
            return try BroadcastPCMDecoder.mono(planes: planes, frames: sample.numSamples, format: format)
        }
        return (format, mono)
    }
}
