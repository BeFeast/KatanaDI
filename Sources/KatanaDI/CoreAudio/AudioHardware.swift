import AudioToolbox
import CoreAudio
import Foundation

enum AudioHardwareError: LocalizedError {
    case propertyQueryFailed(context: String, status: OSStatus)
    case missingAudioUnitComponent

    var errorDescription: String? {
        switch self {
        case .propertyQueryFailed(let context, let status):
            return "\(context) failed with OSStatus \(status)"
        case .missingAudioUnitComponent:
            return "Failed to locate AUHAL component"
        }
    }
}

enum AudioHardware {
    static func allDevices() throws -> [AudioDeviceDescriptor] {
        var address = propertyAddress(
            selector: kAudioHardwarePropertyDevices,
            scope: kAudioObjectPropertyScopeGlobal
        )
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        let dataSize = try getPropertyDataSize(objectID: systemObjectID, address: &address)
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
        guard count > 0 else {
            return []
        }

        var deviceIDs = Array(repeating: AudioDeviceID(bitPattern: 0), count: count)
        var mutableDataSize = dataSize
        let status = deviceIDs.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(
                systemObjectID,
                &address,
                0,
                nil,
                &mutableDataSize,
                buffer.baseAddress!
            )
        }
        guard status == noErr else {
            throw AudioHardwareError.propertyQueryFailed(
                context: "Reading audio device list",
                status: status
            )
        }

        return try deviceIDs.map(deviceDescriptor(for:))
    }

    static func deviceDescriptor(for deviceID: AudioDeviceID) throws -> AudioDeviceDescriptor {
        AudioDeviceDescriptor(
            id: deviceID,
            uid: try stringProperty(
                objectID: deviceID,
                address: propertyAddress(selector: kAudioDevicePropertyDeviceUID, scope: kAudioObjectPropertyScopeGlobal)
            ),
            name: try stringProperty(
                objectID: deviceID,
                address: propertyAddress(selector: kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)
            ),
            manufacturer: try stringProperty(
                objectID: deviceID,
                address: propertyAddress(selector: kAudioObjectPropertyManufacturer, scope: kAudioObjectPropertyScopeGlobal)
            ),
            nominalSampleRate: try scalarProperty(
                objectID: deviceID,
                address: propertyAddress(selector: kAudioDevicePropertyNominalSampleRate, scope: kAudioObjectPropertyScopeGlobal),
                defaultValue: Float64.zero
            ),
            inputChannelCount: try channelCount(
                deviceID: deviceID,
                scope: kAudioObjectPropertyScopeInput
            ),
            outputChannelCount: try channelCount(
                deviceID: deviceID,
                scope: kAudioObjectPropertyScopeOutput
            ),
            bufferFrameSize: Int(try scalarProperty(
                objectID: deviceID,
                address: propertyAddress(selector: kAudioDevicePropertyBufferFrameSize, scope: kAudioObjectPropertyScopeGlobal),
                defaultValue: UInt32.zero
            ))
        )
    }

    static func setBufferFrameSize(_ frameSize: UInt32, for deviceID: AudioDeviceID) throws {
        var value = frameSize
        var address = propertyAddress(
            selector: kAudioDevicePropertyBufferFrameSize,
            scope: kAudioObjectPropertyScopeGlobal
        )
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout.size(ofValue: value)),
            &value
        )
        if status != noErr {
            throw AudioHardwareError.propertyQueryFailed(
                context: "Setting device buffer frame size",
                status: status
            )
        }
    }

    static func setNominalSampleRate(_ sampleRate: Double, for deviceID: AudioDeviceID) throws {
        var value = sampleRate
        var address = propertyAddress(
            selector: kAudioDevicePropertyNominalSampleRate,
            scope: kAudioObjectPropertyScopeGlobal
        )
        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout.size(ofValue: value)),
            &value
        )
        if status != noErr {
            throw AudioHardwareError.propertyQueryFailed(
                context: "Setting device sample rate",
                status: status
            )
        }
    }

    static func defaultOutputDeviceID() throws -> AudioDeviceID {
        try scalarProperty(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: propertyAddress(selector: kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal),
            defaultValue: AudioDeviceID.zero
        )
    }

    static func defaultOutputDeviceDescriptor() throws -> AudioDeviceDescriptor {
        try deviceDescriptor(for: defaultOutputDeviceID())
    }

    static func propertyAddress(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }

    static func stringProperty(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress
    ) throws -> String {
        var localAddress = address
        var value: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                objectID,
                &localAddress,
                0,
                nil,
                &dataSize,
                pointer
            )
        }
        guard status == noErr else {
            throw AudioHardwareError.propertyQueryFailed(
                context: "Reading string property \(address.mSelector)",
                status: status
            )
        }

        return (value as String?) ?? ""
    }

    static func scalarProperty<T>(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        defaultValue: T
    ) throws -> T {
        var localAddress = address
        var value = defaultValue
        var dataSize = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                objectID,
                &localAddress,
                0,
                nil,
                &dataSize,
                pointer
            )
        }
        guard status == noErr else {
            throw AudioHardwareError.propertyQueryFailed(
                context: "Reading scalar property \(address.mSelector)",
                status: status
            )
        }
        return value
    }

    static func makeHALAudioUnit() throws -> AudioUnit {
        try makeAudioUnit(subType: kAudioUnitSubType_HALOutput)
    }

    static func makeDefaultOutputAudioUnit() throws -> AudioUnit {
        try makeAudioUnit(subType: kAudioUnitSubType_DefaultOutput)
    }

    static func makeAudioUnit(subType: OSType) throws -> AudioUnit {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: subType,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &description) else {
            throw AudioHardwareError.missingAudioUnitComponent
        }

        var audioUnit: AudioUnit?
        let status = AudioComponentInstanceNew(component, &audioUnit)
        guard status == noErr, let audioUnit else {
            throw AudioHardwareError.propertyQueryFailed(
                context: "Creating AUHAL instance",
                status: status
            )
        }
        return audioUnit
    }

    private static func getPropertyDataSize(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) throws -> UInt32 {
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            objectID,
            &address,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else {
            throw AudioHardwareError.propertyQueryFailed(
                context: "Reading property size \(address.mSelector)",
                status: status
            )
        }
        return dataSize
    }

    private static func channelCount(
        deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) throws -> Int {
        var address = propertyAddress(
            selector: kAudioDevicePropertyStreamConfiguration,
            scope: scope
        )
        let dataSize = try getPropertyDataSize(objectID: deviceID, address: &address)
        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            rawPointer.deallocate()
        }

        var mutableDataSize = dataSize
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &mutableDataSize,
            rawPointer
        )
        guard status == noErr else {
            throw AudioHardwareError.propertyQueryFailed(
                context: "Reading stream configuration",
                status: status
            )
        }

        let bufferList = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        return UnsafeMutableAudioBufferListPointer(bufferList).reduce(0) { partialResult, buffer in
            partialResult + Int(buffer.mNumberChannels)
        }
    }
}
