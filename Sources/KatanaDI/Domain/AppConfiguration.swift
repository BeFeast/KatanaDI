import Foundation

enum OutputMode: String, Codable, CaseIterable, Sendable {
    case monoLeft = "mono-left"
    case monoRight = "mono-right"
    case stereo = "stereo"

    var menuTitle: String {
        switch self {
        case .monoLeft:
            return "Mono -> Left"
        case .monoRight:
            return "Mono -> Right"
        case .stereo:
            return "Mono -> Stereo"
        }
    }
}

struct AppConfiguration: Codable, Equatable, Sendable {
    static let defaults = AppConfiguration()
    static let supportedBufferSizes = [64, 128, 256, 512]

    var inputDeviceQuery: String
    var inputChannel: Int
    var outputDeviceQuery: String
    var outputMode: OutputMode
    var bufferSize: Int
    var preferredSampleRate: Double?
    var autoStart: Bool
    var startAtLogin: Bool

    init(
        inputDeviceQuery: String = "KATANA",
        inputChannel: Int = 3,
        outputDeviceQuery: String = "Built-in Output",
        outputMode: OutputMode = .stereo,
        bufferSize: Int = 128,
        preferredSampleRate: Double? = nil,
        autoStart: Bool = true,
        startAtLogin: Bool = false
    ) {
        self.inputDeviceQuery = inputDeviceQuery
        self.inputChannel = max(1, inputChannel)
        self.outputDeviceQuery = outputDeviceQuery
        self.outputMode = outputMode
        self.bufferSize = Self.supportedBufferSizes.contains(bufferSize) ? bufferSize : 128
        self.preferredSampleRate = preferredSampleRate
        self.autoStart = autoStart
        self.startAtLogin = startAtLogin
    }
}
