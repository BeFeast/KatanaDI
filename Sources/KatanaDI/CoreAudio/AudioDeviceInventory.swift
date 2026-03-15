import Foundation

struct AudioDeviceInventory {
    let devices: [AudioDeviceDescriptor]

    func firstInputDevice(matching query: String) -> AudioDeviceDescriptor? {
        devices.first(where: { $0.inputChannelCount > 0 && $0.matches(query) })
    }

    func firstOutputDevice(matching query: String) -> AudioDeviceDescriptor? {
        devices.first(where: { $0.outputChannelCount > 0 && $0.matches(query) })
    }
}
