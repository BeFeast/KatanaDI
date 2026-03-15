import CoreAudio
import Foundation

final class AudioDeviceMonitor {
    var onDevicesChanged: (() -> Void)?

    private let queue = DispatchQueue(label: "com.oklabs.katanadi.device-monitor")
    private var devicesListener: AudioObjectPropertyListenerBlock?
    private var isStarted = false

    func start() throws {
        guard isStarted == false else {
            return
        }

        var address = AudioHardware.propertyAddress(
            selector: kAudioHardwarePropertyDevices,
            scope: kAudioObjectPropertyScopeGlobal
        )

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Log.devices.info("Detected audio device inventory change")
            self?.onDevicesChanged?()
        }

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            listener
        )
        guard status == noErr else {
            throw AudioHardwareError.propertyQueryFailed(
                context: "Registering audio device listener",
                status: status
            )
        }

        devicesListener = listener
        isStarted = true
    }

    func stop() {
        guard isStarted, let listener = devicesListener else {
            return
        }

        var address = AudioHardware.propertyAddress(
            selector: kAudioHardwarePropertyDevices,
            scope: kAudioObjectPropertyScopeGlobal
        )

        let status = AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            listener
        )
        if status != noErr {
            Log.devices.error("Failed to remove audio device listener: \(status)")
        }

        devicesListener = nil
        isStarted = false
    }

    func currentInventory() throws -> AudioDeviceInventory {
        AudioDeviceInventory(devices: try AudioHardware.allDevices())
    }
}
