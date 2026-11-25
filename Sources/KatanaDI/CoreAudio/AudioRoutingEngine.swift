import AudioToolbox
import AudioUnit
import CoreAudio
import Foundation
import os.lock

enum AudioRoutingError: LocalizedError {
    case outputSampleRateMismatch(expected: Double, actual: Double)
    case unsupportedOutputTopology(channelCount: Int)
    case callbackBufferTooSmall(requestedFrames: UInt32)
    case missingIOData
    case outputDeviceNotCurrentDefault(expected: String, actual: String)
    case unitPropertyFailed(context: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .outputSampleRateMismatch(let expected, let actual):
            return "Built-in Output is running at \(Int(actual.rounded())) Hz, but routing needs \(Int(expected.rounded())) Hz"
        case .unsupportedOutputTopology(let channelCount):
            return "Output device exposes unsupported topology with \(channelCount) channel(s)"
        case .callbackBufferTooSmall(let requestedFrames):
            return "Render callback requested \(requestedFrames) frames, which exceeds the preallocated buffer"
        case .missingIOData:
            return "Output callback received no output buffer"
        case .outputDeviceNotCurrentDefault(let expected, let actual):
            return "System output must be \(expected). Current default output is \(actual)"
        case .unitPropertyFailed(let context, let status):
            return "\(context) failed with OSStatus \(status)"
        }
    }
}

final class AudioRoutingEngine {
    private static let inputElement: UInt32 = 1

    private struct DiagnosticsState {
        var ringBufferFillFrames = 0
        var ringBufferCapacityFrames = 0
        var targetFillFrames = 0
        var inputCallbackCount: UInt64 = 0
        var outputCallbackCount: UInt64 = 0
        var inputPeak: Float = 0
        var outputPeak: Float = 0
        var underflowCount: UInt64 = 0
        var overflowCount: UInt64 = 0
        var droppedFrameCount: UInt64 = 0
        var duplicatedFrameCount: UInt64 = 0
    }

    private struct RouteSignature: Equatable {
        let inputDeviceID: AudioDeviceID
        let outputDeviceID: AudioDeviceID
        let inputChannel: Int
        let outputMode: OutputMode
        let bufferSize: Int
        let sampleRate: Double
    }

    private var inputUnit: AudioUnit?
    private var outputUnit: AudioUnit?
    private var ringBuffer: PCMFloatRingBuffer?
    private var currentSignature: RouteSignature?
    private var currentRuntime: RouteRuntimeState?
    private var outputMode: OutputMode = .stereo
    private var selectedInputChannelIndex = 0
    private var inputChannelCount = 1
    private var maxFramesPerSlice: UInt32 = 4096
    private var targetBufferFillFrames = 0
    private var highWaterBufferFillFrames = 0
    private var lowWaterBufferFillFrames = 0

    private var inputBufferListPointer: UnsafeMutablePointer<AudioBufferList>?
    private var inputChannelBufferMemory: [UnsafeMutableRawPointer] = []
    private var inputSelectionScratchMemory: UnsafeMutablePointer<Float>?
    private var readScratchMemory: UnsafeMutablePointer<Float>?
    private var diagnosticsLock = os_unfair_lock_s()
    private var diagnosticsState = DiagnosticsState()

    func startOrUpdate(
        inputDevice: AudioDeviceDescriptor,
        outputDevice: AudioDeviceDescriptor,
        configuration: AppConfiguration
    ) throws -> RouteRuntimeState {
        let requestedSampleRate = configuration.preferredSampleRate ?? inputDevice.nominalSampleRate

        let targetSignature = RouteSignature(
            inputDeviceID: inputDevice.id,
            outputDeviceID: outputDevice.id,
            inputChannel: configuration.inputChannel,
            outputMode: configuration.outputMode,
            bufferSize: configuration.bufferSize,
            sampleRate: requestedSampleRate
        )

        if let currentSignature, currentSignature == targetSignature, let currentRuntime {
            return currentRuntime
        }

        stop()

        let defaultOutputDevice = try AudioHardware.defaultOutputDeviceDescriptor()
        guard defaultOutputDevice.id == outputDevice.id else {
            throw AudioRoutingError.outputDeviceNotCurrentDefault(
                expected: outputDevice.name,
                actual: defaultOutputDevice.name
            )
        }

        try configureOutputDevice(defaultOutputDevice.id, requestedSampleRate: requestedSampleRate)
        try configureBufferSizes(inputDeviceID: inputDevice.id, outputDeviceID: defaultOutputDevice.id, frameSize: UInt32(configuration.bufferSize))

        let actualOutputDevice = try AudioHardware.deviceDescriptor(for: defaultOutputDevice.id)
        guard abs(actualOutputDevice.nominalSampleRate - requestedSampleRate) < 0.5 else {
            throw AudioRoutingError.outputSampleRateMismatch(
                expected: requestedSampleRate,
                actual: actualOutputDevice.nominalSampleRate
            )
        }

        guard actualOutputDevice.outputChannelCount >= 1 else {
            throw AudioRoutingError.unsupportedOutputTopology(channelCount: actualOutputDevice.outputChannelCount)
        }

        outputMode = configuration.outputMode
        selectedInputChannelIndex = configuration.inputChannel - 1
        inputChannelCount = inputDevice.inputChannelCount
        maxFramesPerSlice = UInt32(max(configuration.bufferSize * 8, 4096))
        ringBuffer = PCMFloatRingBuffer(capacity: Int(requestedSampleRate.rounded()))
        targetBufferFillFrames = max(configuration.bufferSize * 6, 512)
        lowWaterBufferFillFrames = max(configuration.bufferSize * 2, targetBufferFillFrames - (configuration.bufferSize * 2))
        highWaterBufferFillFrames = min(Int(requestedSampleRate.rounded()) - 1, targetBufferFillFrames + (configuration.bufferSize * 2))
        allocateInputBuffers(channelCount: inputDevice.inputChannelCount, maxFrames: Int(maxFramesPerSlice))
        allocateInputSelectionScratchBuffer(maxFrames: Int(maxFramesPerSlice))
        allocateReadScratchBuffer(maxFrames: Int(maxFramesPerSlice))
        resetDiagnostics(ringBufferCapacityFrames: Int(requestedSampleRate.rounded()))

        let inputUnit = try AudioHardware.makeHALAudioUnit()
        let outputUnit = try AudioHardware.makeDefaultOutputAudioUnit()

        try configureInputUnit(
            inputUnit,
            deviceID: inputDevice.id,
            channelCount: inputDevice.inputChannelCount,
            sampleRate: requestedSampleRate
        )
        try configureOutputUnit(
            outputUnit,
            sampleRate: requestedSampleRate
        )

        let initInputStatus = AudioUnitInitialize(inputUnit)
        guard initInputStatus == noErr else {
            throw AudioRoutingError.unitPropertyFailed(
                context: "Initializing input audio unit",
                status: initInputStatus
            )
        }

        let initOutputStatus = AudioUnitInitialize(outputUnit)
        guard initOutputStatus == noErr else {
            throw AudioRoutingError.unitPropertyFailed(
                context: "Initializing output audio unit",
                status: initOutputStatus
            )
        }

        let inputStartStatus = AudioOutputUnitStart(inputUnit)
        guard inputStartStatus == noErr else {
            throw AudioRoutingError.unitPropertyFailed(
                context: "Starting input audio unit",
                status: inputStartStatus
            )
        }

        let outputStartStatus = AudioOutputUnitStart(outputUnit)
        guard outputStartStatus == noErr else {
            throw AudioRoutingError.unitPropertyFailed(
                context: "Starting output audio unit",
                status: outputStartStatus
            )
        }

        self.inputUnit = inputUnit
        self.outputUnit = outputUnit
        currentSignature = targetSignature

        let runtime = RouteRuntimeState(
            inputDeviceName: inputDevice.name,
            outputDeviceName: actualOutputDevice.name,
            inputChannel: configuration.inputChannel,
            outputMode: configuration.outputMode,
            sampleRate: requestedSampleRate,
            bufferSize: configuration.bufferSize
        )

        currentRuntime = runtime
        Log.audio.info("Routing active: \(runtime.inputDeviceName, privacy: .public) -> \(runtime.outputDeviceName, privacy: .public), channel \(runtime.inputChannel), buffer \(runtime.bufferSize), sample rate \(Int(runtime.sampleRate.rounded()))")
        return runtime
    }

    func stop() {
        if let outputUnit {
            AudioOutputUnitStop(outputUnit)
            AudioUnitUninitialize(outputUnit)
            AudioComponentInstanceDispose(outputUnit)
        }

        if let inputUnit {
            AudioOutputUnitStop(inputUnit)
            AudioUnitUninitialize(inputUnit)
            AudioComponentInstanceDispose(inputUnit)
        }

        inputUnit = nil
        outputUnit = nil
        currentSignature = nil
        currentRuntime = nil
        selectedInputChannelIndex = 0
        inputChannelCount = 1
        targetBufferFillFrames = 0
        lowWaterBufferFillFrames = 0
        highWaterBufferFillFrames = 0
        ringBuffer?.clear()
        ringBuffer = nil
        resetDiagnostics(ringBufferCapacityFrames: 0)
    }

    deinit {
        stop()
        deallocateInputBuffers()
        deallocateInputSelectionScratchBuffer()
        deallocateReadScratchBuffer()
    }

    func diagnosticsSnapshot() -> AudioEngineDiagnosticsSnapshot? {
        guard currentRuntime != nil else {
            return nil
        }

        os_unfair_lock_lock(&diagnosticsLock)
        let state = diagnosticsState
        os_unfair_lock_unlock(&diagnosticsLock)

        return AudioEngineDiagnosticsSnapshot(
            ringBufferFillFrames: state.ringBufferFillFrames,
            ringBufferCapacityFrames: state.ringBufferCapacityFrames,
            targetFillFrames: state.targetFillFrames,
            inputCallbackCount: state.inputCallbackCount,
            outputCallbackCount: state.outputCallbackCount,
            inputPeak: state.inputPeak,
            outputPeak: state.outputPeak,
            underflowCount: state.underflowCount,
            overflowCount: state.overflowCount,
            droppedFrameCount: state.droppedFrameCount,
            duplicatedFrameCount: state.duplicatedFrameCount
        )
    }

    private func configureOutputDevice(_ deviceID: AudioDeviceID, requestedSampleRate: Double) throws {
        let outputDevice = try AudioHardware.deviceDescriptor(for: deviceID)
        if abs(outputDevice.nominalSampleRate - requestedSampleRate) > 0.5 {
            try AudioHardware.setNominalSampleRate(requestedSampleRate, for: deviceID)
        }
    }

    private func configureBufferSizes(inputDeviceID: AudioDeviceID, outputDeviceID: AudioDeviceID, frameSize: UInt32) throws {
        do {
            try AudioHardware.setBufferFrameSize(frameSize, for: inputDeviceID)
        } catch {
            Log.audio.error("Failed to set input buffer size: \(error.localizedDescription, privacy: .public)")
        }

        do {
            try AudioHardware.setBufferFrameSize(frameSize, for: outputDeviceID)
        } catch {
            Log.audio.error("Failed to set output buffer size: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func allocateInputBuffers(channelCount: Int, maxFrames: Int) {
        deallocateInputBuffers()

        let safeChannelCount = max(channelCount, 1)
        let audioBufferListSize = MemoryLayout<AudioBufferList>.size + max(0, safeChannelCount - 1) * MemoryLayout<AudioBuffer>.size
        let listPointer = UnsafeMutableRawPointer.allocate(
            byteCount: audioBufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        ).bindMemory(to: AudioBufferList.self, capacity: 1)

        listPointer.pointee.mNumberBuffers = UInt32(safeChannelCount)

        let byteCount = maxFrames * MemoryLayout<Float>.stride
        let buffers = UnsafeMutableAudioBufferListPointer(listPointer)
        inputChannelBufferMemory = []
        inputChannelBufferMemory.reserveCapacity(safeChannelCount)

        for index in 0..<safeChannelCount {
            let channelMemory = UnsafeMutableRawPointer.allocate(
                byteCount: byteCount,
                alignment: MemoryLayout<Float>.alignment
            )
            channelMemory.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)

            buffers[index] = AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(byteCount),
                mData: channelMemory
            )
            inputChannelBufferMemory.append(channelMemory)
        }

        inputBufferListPointer = listPointer
    }

    private func allocateReadScratchBuffer(maxFrames: Int) {
        deallocateReadScratchBuffer()

        let readScratchMemory = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
        readScratchMemory.initialize(repeating: 0, count: maxFrames)
        self.readScratchMemory = readScratchMemory
    }

    private func allocateInputSelectionScratchBuffer(maxFrames: Int) {
        deallocateInputSelectionScratchBuffer()

        let inputSelectionScratchMemory = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
        inputSelectionScratchMemory.initialize(repeating: 0, count: maxFrames)
        self.inputSelectionScratchMemory = inputSelectionScratchMemory
    }

    private func deallocateInputBuffers() {
        for memory in inputChannelBufferMemory {
            memory.deallocate()
        }
        inputChannelBufferMemory.removeAll(keepingCapacity: false)
        inputBufferListPointer?.deallocate()
        inputBufferListPointer = nil
    }

    private func deallocateReadScratchBuffer() {
        readScratchMemory?.deallocate()
        readScratchMemory = nil
    }

    private func deallocateInputSelectionScratchBuffer() {
        inputSelectionScratchMemory?.deallocate()
        inputSelectionScratchMemory = nil
    }

    private func configureInputUnit(
        _ audioUnit: AudioUnit,
        deviceID: AudioDeviceID,
        channelCount: Int,
        sampleRate: Double
    ) throws {
        var enableInput: UInt32 = 1
        try setAudioUnitProperty(
            audioUnit,
            propertyID: kAudioOutputUnitProperty_EnableIO,
            scope: kAudioUnitScope_Input,
            element: 1,
            value: &enableInput
        )

        var disableOutput: UInt32 = 0
        try setAudioUnitProperty(
            audioUnit,
            propertyID: kAudioOutputUnitProperty_EnableIO,
            scope: kAudioUnitScope_Output,
            element: 0,
            value: &disableOutput
        )

        var currentDevice = deviceID
        try setAudioUnitProperty(
            audioUnit,
            propertyID: kAudioOutputUnitProperty_CurrentDevice,
            scope: kAudioUnitScope_Global,
            element: 0,
            value: &currentDevice
        )

        var streamFormat = makePCMFloatFormat(sampleRate: sampleRate, channels: UInt32(max(channelCount, 1)))
        try setAudioUnitProperty(
            audioUnit,
            propertyID: kAudioUnitProperty_StreamFormat,
            scope: kAudioUnitScope_Output,
            element: 1,
            value: &streamFormat
        )

        var callback = AURenderCallbackStruct(
            inputProc: inputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        try setAudioUnitProperty(
            audioUnit,
            propertyID: kAudioOutputUnitProperty_SetInputCallback,
            scope: kAudioUnitScope_Global,
            element: 0,
            value: &callback
        )
    }

    private func configureOutputUnit(
        _ audioUnit: AudioUnit,
        sampleRate: Double
    ) throws {
        var streamFormat = makePCMFloatFormat(sampleRate: sampleRate, channels: 2)
        try setAudioUnitProperty(
            audioUnit,
            propertyID: kAudioUnitProperty_StreamFormat,
            scope: kAudioUnitScope_Input,
            element: 0,
            value: &streamFormat
        )

        var callback = AURenderCallbackStruct(
            inputProc: outputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        try setAudioUnitProperty(
            audioUnit,
            propertyID: kAudioUnitProperty_SetRenderCallback,
            scope: kAudioUnitScope_Input,
            element: 0,
            value: &callback
        )
    }

    private func setAudioUnitProperty<T>(
        _ audioUnit: AudioUnit,
        propertyID: AudioUnitPropertyID,
        scope: AudioUnitScope,
        element: AudioUnitElement,
        value: inout T
    ) throws {
        let valueSize = UInt32(MemoryLayout.size(ofValue: value))
        let status = withUnsafePointer(to: &value) { pointer in
            AudioUnitSetProperty(
                audioUnit,
                propertyID,
                scope,
                element,
                pointer,
                valueSize
            )
        }
        guard status == noErr else {
            throw AudioRoutingError.unitPropertyFailed(
                context: "Setting audio unit property \(propertyID)",
                status: status
            )
        }
    }

    private func makePCMFloatFormat(sampleRate: Double, channels: UInt32) -> AudioStreamBasicDescription {
        let bytesPerSample = UInt32(MemoryLayout<Float>.size)
        return AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: bytesPerSample,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerSample,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 8 * bytesPerSample,
            mReserved: 0
        )
    }

    fileprivate func handleInputCallback(
        ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>?,
        timeStamp: UnsafePointer<AudioTimeStamp>,
        busNumber _: UInt32,
        frameCount: UInt32
    ) -> OSStatus {
        guard let inputUnit, let ringBuffer, let inputBufferListPointer else {
            return noErr
        }

        guard frameCount <= maxFramesPerSlice else {
            return kAudio_ParamError
        }

        let inputBuffers = UnsafeMutableAudioBufferListPointer(inputBufferListPointer)
        for index in 0..<inputBuffers.count {
            inputBuffers[index].mDataByteSize = frameCount * UInt32(MemoryLayout<Float>.size)
        }

        let renderStatus = AudioUnitRender(
            inputUnit,
            ioActionFlags,
            timeStamp,
            Self.inputElement,
            frameCount,
            inputBufferListPointer
        )
        guard renderStatus == noErr else {
            return renderStatus
        }

        let requestedFrames = Int(frameCount)

        if selectedInputChannelIndex >= 0, selectedInputChannelIndex < inputBuffers.count, inputBuffers[selectedInputChannelIndex].mNumberChannels == 1 {
            let selectedBuffer = inputBuffers[selectedInputChannelIndex]
            guard let mData = selectedBuffer.mData else {
                return noErr
            }

            let floatPointer = mData.assumingMemoryBound(to: Float.self)
            let writeResult = ringBuffer.write(floatPointer, frameCount: requestedFrames)
            updateInputDiagnostics(
                source: floatPointer,
                frameCount: requestedFrames,
                writeResult: writeResult
            )
            return noErr
        }

        guard
            inputBuffers.count == 1,
            let scratch = inputSelectionScratchMemory
        else {
            return kAudio_ParamError
        }

        let interleavedBuffer = inputBuffers[0]
        guard
            let mData = interleavedBuffer.mData,
            selectedInputChannelIndex < Int(interleavedBuffer.mNumberChannels)
        else {
            return kAudio_ParamError
        }

        let interleavedPointer = mData.assumingMemoryBound(to: Float.self)
        let channelCount = Int(interleavedBuffer.mNumberChannels)
        for frame in 0..<requestedFrames {
            scratch[frame] = interleavedPointer[(frame * channelCount) + selectedInputChannelIndex]
        }

        let writeResult = ringBuffer.write(scratch, frameCount: requestedFrames)
        updateInputDiagnostics(
            source: UnsafePointer(scratch),
            frameCount: requestedFrames,
            writeResult: writeResult
        )
        return noErr
    }

    fileprivate func handleOutputCallback(
        frameCount: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>?
    ) -> OSStatus {
        guard frameCount <= maxFramesPerSlice else {
            return kAudio_ParamError
        }

        guard let ioData, let ringBuffer, let readScratchMemory else {
            return kAudio_ParamError
        }

        let buffers = UnsafeMutableAudioBufferListPointer(ioData)
        guard buffers.isEmpty == false else {
            return noErr
        }

        let requestedFrames = Int(frameCount)
        let availableBeforeRead = ringBuffer.snapshot().availableFrames

        var framesToConsume = requestedFrames
        var duplicatedFrames = 0
        if availableBeforeRead > requestedFrames, availableBeforeRead < lowWaterBufferFillFrames {
            framesToConsume = requestedFrames - 1
            duplicatedFrames = 1
        }

        let framesRead = ringBuffer.read(into: readScratchMemory, frameCount: framesToConsume)
        if duplicatedFrames > 0, framesRead == framesToConsume, framesRead > 0 {
            readScratchMemory[requestedFrames - 1] = readScratchMemory[framesRead - 1]
        }

        let producedFrames = framesRead + duplicatedFrames
        if producedFrames < requestedFrames {
            readScratchMemory.advanced(by: producedFrames).initialize(repeating: 0, count: requestedFrames - producedFrames)
        }

        var droppedFrames = 0
        let availableAfterRead = ringBuffer.snapshot().availableFrames
        if availableAfterRead > highWaterBufferFillFrames {
            droppedFrames = ringBuffer.discard(frameCount: 1)
        }

        updateOutputDiagnostics(
            source: UnsafePointer(readScratchMemory),
            frameCount: requestedFrames,
            availableFrames: ringBuffer.snapshot().availableFrames,
            underflowed: producedFrames < requestedFrames,
            droppedFrames: droppedFrames,
            duplicatedFrames: duplicatedFrames
        )

        if buffers.count == 1, buffers[0].mNumberChannels > 1 {
            writeInterleavedOutput(
                readScratchMemory,
                frameCount: requestedFrames,
                buffer: buffers[0],
                outputMode: outputMode
            )
            return noErr
        }

        switch outputMode {
        case .monoLeft:
            writeMonoToSingleBuffer(readScratchMemory, frameCount: requestedFrames, buffer: buffers[0])
            if buffers.count > 1 {
                clearBuffer(buffers[1], frameCount: requestedFrames)
            }
        case .monoRight:
            clearBuffer(buffers[0], frameCount: requestedFrames)
            if buffers.count > 1 {
                writeMonoToSingleBuffer(readScratchMemory, frameCount: requestedFrames, buffer: buffers[1])
            }
        case .stereo:
            writeMonoToSingleBuffer(readScratchMemory, frameCount: requestedFrames, buffer: buffers[0])
            if buffers.count > 1 {
                writeMonoToSingleBuffer(readScratchMemory, frameCount: requestedFrames, buffer: buffers[1])
            }
        }

        return noErr
    }

    private func writeMonoToSingleBuffer(
        _ source: UnsafePointer<Float>,
        frameCount: Int,
        buffer: AudioBuffer
    ) {
        guard let mData = buffer.mData else {
            return
        }

        let destination = mData.assumingMemoryBound(to: Float.self)
        destination.update(from: source, count: frameCount)
    }

    private func clearBuffer(_ buffer: AudioBuffer, frameCount: Int) {
        guard let mData = buffer.mData else {
            return
        }

        let destination = mData.assumingMemoryBound(to: Float.self)
        destination.initialize(repeating: 0, count: frameCount)
    }

    private func resetDiagnostics(ringBufferCapacityFrames: Int) {
        os_unfair_lock_lock(&diagnosticsLock)
        diagnosticsState = DiagnosticsState(
            ringBufferFillFrames: 0,
            ringBufferCapacityFrames: ringBufferCapacityFrames,
            targetFillFrames: targetBufferFillFrames
        )
        os_unfair_lock_unlock(&diagnosticsLock)
    }

    private func updateInputDiagnostics(
        source: UnsafePointer<Float>,
        frameCount: Int,
        writeResult: PCMFloatRingBuffer.WriteResult
    ) {
        let peak = peakValue(source: source, frameCount: frameCount)
        os_unfair_lock_lock(&diagnosticsLock)
        diagnosticsState.inputCallbackCount += 1
        diagnosticsState.inputPeak = max(peak, diagnosticsState.inputPeak * 0.92)
        diagnosticsState.ringBufferFillFrames = writeResult.availableFrames
        diagnosticsState.ringBufferCapacityFrames = writeResult.capacity
        diagnosticsState.targetFillFrames = targetBufferFillFrames
        diagnosticsState.overflowCount += UInt64(writeResult.overwrittenFrames > 0 ? 1 : 0)
        diagnosticsState.droppedFrameCount += UInt64(writeResult.overwrittenFrames)
        os_unfair_lock_unlock(&diagnosticsLock)
    }

    private func updateOutputDiagnostics(
        source: UnsafePointer<Float>,
        frameCount: Int,
        availableFrames: Int,
        underflowed: Bool,
        droppedFrames: Int,
        duplicatedFrames: Int
    ) {
        let peak = peakValue(source: source, frameCount: frameCount)
        os_unfair_lock_lock(&diagnosticsLock)
        diagnosticsState.outputCallbackCount += 1
        diagnosticsState.outputPeak = max(peak, diagnosticsState.outputPeak * 0.92)
        diagnosticsState.ringBufferFillFrames = availableFrames
        diagnosticsState.ringBufferCapacityFrames = ringBuffer?.snapshot().capacity ?? diagnosticsState.ringBufferCapacityFrames
        diagnosticsState.targetFillFrames = targetBufferFillFrames
        diagnosticsState.underflowCount += UInt64(underflowed ? 1 : 0)
        diagnosticsState.droppedFrameCount += UInt64(droppedFrames)
        diagnosticsState.duplicatedFrameCount += UInt64(duplicatedFrames)
        os_unfair_lock_unlock(&diagnosticsLock)
    }

    private func peakValue(source: UnsafePointer<Float>, frameCount: Int) -> Float {
        guard frameCount > 0 else {
            return 0
        }

        var peak: Float = 0
        for frame in 0..<frameCount {
            peak = max(peak, abs(source[frame]))
        }
        return peak
    }

    private func writeInterleavedOutput(
        _ source: UnsafePointer<Float>,
        frameCount: Int,
        buffer: AudioBuffer,
        outputMode: OutputMode
    ) {
        guard
            let mData = buffer.mData,
            buffer.mNumberChannels > 0
        else {
            return
        }

        let channelCount = Int(buffer.mNumberChannels)
        let destination = mData.assumingMemoryBound(to: Float.self)

        for frame in 0..<frameCount {
            let sourceSample = source[frame]
            for channel in 0..<channelCount {
                let value: Float
                switch outputMode {
                case .monoLeft:
                    value = channel == 0 ? sourceSample : 0
                case .monoRight:
                    value = channel == 1 ? sourceSample : 0
                case .stereo:
                    value = channel < 2 ? sourceSample : 0
                }
                destination[(frame * channelCount) + channel] = value
            }
        }
    }
}

private let inputCallback: AURenderCallback = { refCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, _ in
    let engine = Unmanaged<AudioRoutingEngine>.fromOpaque(refCon).takeUnretainedValue()
    return engine.handleInputCallback(
        ioActionFlags: ioActionFlags,
        timeStamp: inTimeStamp,
        busNumber: inBusNumber,
        frameCount: inNumberFrames
    )
}

private let outputCallback: AURenderCallback = { refCon, _, _, _, inNumberFrames, ioData in
    let engine = Unmanaged<AudioRoutingEngine>.fromOpaque(refCon).takeUnretainedValue()
    return engine.handleOutputCallback(
        frameCount: inNumberFrames,
        ioData: ioData
    )
}
