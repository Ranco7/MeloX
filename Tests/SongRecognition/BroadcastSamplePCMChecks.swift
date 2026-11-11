// macOS standalone adapter test: creates real CMSampleBuffers, no capture device.
import AudioToolbox
import CoreMedia
import Foundation

@main
struct BroadcastSamplePCMChecks {
    static func main() throws {
        var asbd = AudioStreamBasicDescription(mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: 0xe, mBytesPerPacket: 4, mFramesPerPacket: 1,
            mBytesPerFrame: 4, mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0)
        var description: CMAudioFormatDescription?
        precondition(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &description) == noErr)
        let data = Data([0x40, 0, 0, 0, 0xc0, 0, 0x40, 0])
        var block: CMBlockBuffer?
        precondition(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: data.count, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: data.count, flags: 0, blockBufferOut: &block) == noErr)
        data.withUnsafeBytes { bytes in
            precondition(CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block!,
                offsetIntoDestination: 0, dataLength: data.count) == noErr)
        }
        var sample: CMSampleBuffer?
        // Deliberately use a PTS timescale unrelated to the ASBD sample rate.
        precondition(CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault,
            dataBuffer: block!, formatDescription: description!, sampleCount: 2,
            presentationTimeStamp: CMTime(value: 1_000_000, timescale: 1_000_000),
            packetDescriptions: nil, sampleBufferOut: &sample) == noErr)
        let (format, mono) = try BroadcastSamplePCM.decode(sample!)
        precondition(format.rate == 44_100 && format.bigEndian && format.bits == 16)
        precondition(mono == [0.25, 0])
        print("PASS: real CMSampleBuffer ASBD 0xe BE Int16 stereo; PTS timescale is not sample rate")
    }
}
