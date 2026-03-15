import Foundation

struct AudioEngineDiagnosticsSnapshot: Equatable, Sendable {
    let ringBufferFillFrames: Int
    let ringBufferCapacityFrames: Int
    let targetFillFrames: Int
    let inputCallbackCount: UInt64
    let outputCallbackCount: UInt64
    let inputPeak: Float
    let outputPeak: Float
    let underflowCount: UInt64
    let overflowCount: UInt64
    let droppedFrameCount: UInt64
    let duplicatedFrameCount: UInt64

    var ringBufferFillPercent: Int {
        guard ringBufferCapacityFrames > 0 else {
            return 0
        }
        return Int((Double(ringBufferFillFrames) / Double(ringBufferCapacityFrames) * 100).rounded())
    }
}

struct RouteRuntimeState: Equatable, Sendable {
    let inputDeviceName: String
    let outputDeviceName: String
    let inputChannel: Int
    let outputMode: OutputMode
    let sampleRate: Double
    let bufferSize: Int
    let diagnostics: AudioEngineDiagnosticsSnapshot?

    init(
        inputDeviceName: String,
        outputDeviceName: String,
        inputChannel: Int,
        outputMode: OutputMode,
        sampleRate: Double,
        bufferSize: Int,
        diagnostics: AudioEngineDiagnosticsSnapshot? = nil
    ) {
        self.inputDeviceName = inputDeviceName
        self.outputDeviceName = outputDeviceName
        self.inputChannel = inputChannel
        self.outputMode = outputMode
        self.sampleRate = sampleRate
        self.bufferSize = bufferSize
        self.diagnostics = diagnostics
    }

    func withDiagnostics(_ diagnostics: AudioEngineDiagnosticsSnapshot?) -> RouteRuntimeState {
        RouteRuntimeState(
            inputDeviceName: inputDeviceName,
            outputDeviceName: outputDeviceName,
            inputChannel: inputChannel,
            outputMode: outputMode,
            sampleRate: sampleRate,
            bufferSize: bufferSize,
            diagnostics: diagnostics
        )
    }
}

enum AppStatus: Equatable, Sendable {
    case waiting(String)
    case active(RouteRuntimeState)
    case error(String)

    var statusBadge: String {
        switch self {
        case .waiting:
            return "KDI?"
        case .active:
            return "KDI"
        case .error:
            return "KDI!"
        }
    }

    var tooltip: String {
        switch self {
        case .waiting(let message):
            return "KatanaDI: \(message)"
        case .active(let runtime):
            return "KatanaDI: \(runtime.inputDeviceName) -> \(runtime.outputDeviceName)"
        case .error(let message):
            return "KatanaDI error: \(message)"
        }
    }

    var headline: String {
        switch self {
        case .waiting:
            return "Status: Waiting"
        case .active:
            return "Status: Active"
        case .error:
            return "Status: Error"
        }
    }

    var detailLine: String {
        switch self {
        case .waiting(let message):
            return message
        case .error(let message):
            return message
        case .active(let runtime):
            let sampleRate = Int(runtime.sampleRate.rounded())
            return "\(runtime.inputDeviceName) -> \(runtime.outputDeviceName) | Ch\(runtime.inputChannel) | \(sampleRate) Hz | \(runtime.bufferSize) samples | \(runtime.outputMode.rawValue)"
        }
    }

    var diagnosticLines: [String] {
        guard case .active(let runtime) = self, let diagnostics = runtime.diagnostics else {
            return []
        }

        return [
            "Ring Buffer: \(diagnostics.ringBufferFillFrames)/\(diagnostics.ringBufferCapacityFrames) frames (\(diagnostics.ringBufferFillPercent)%), target \(diagnostics.targetFillFrames)",
            String(
                format: "Signal: input %.4f, output %.4f",
                diagnostics.inputPeak,
                diagnostics.outputPeak
            ),
            "Callbacks: input \(diagnostics.inputCallbackCount), output \(diagnostics.outputCallbackCount)",
            "Corrections: underflows \(diagnostics.underflowCount), overflows \(diagnostics.overflowCount), dropped \(diagnostics.droppedFrameCount), duplicated \(diagnostics.duplicatedFrameCount)"
        ]
    }
}
