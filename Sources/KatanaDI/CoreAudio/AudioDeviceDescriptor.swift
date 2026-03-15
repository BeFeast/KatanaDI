import CoreAudio
import Foundation

struct AudioDeviceDescriptor: Equatable, Hashable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let manufacturer: String
    let nominalSampleRate: Double
    let inputChannelCount: Int
    let outputChannelCount: Int
    let bufferFrameSize: Int

    func matches(_ query: String) -> Bool {
        guard query.isEmpty == false else {
            return true
        }

        return name.localizedCaseInsensitiveContains(query) || uid.localizedCaseInsensitiveContains(query)
    }
}
