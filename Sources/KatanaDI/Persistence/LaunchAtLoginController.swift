import Foundation

struct LaunchAtLoginController {
    private let label = "com.oklabs.katanadi"

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    func sync(enabled: Bool) throws {
        let fileManager = FileManager.default
        let directoryURL = launchAgentURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        if enabled {
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": launchArguments(),
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Interactive",
                "LimitLoadToSessionType": ["Aqua"]
            ]

            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try data.write(to: launchAgentURL, options: .atomic)
        } else if fileManager.fileExists(atPath: launchAgentURL.path) {
            try fileManager.removeItem(at: launchAgentURL)
        }
    }

    private func launchArguments() -> [String] {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        if bundleURL.pathExtension == "app" {
            return ["/usr/bin/open", bundleURL.path]
        }

        let executablePath = URL(fileURLWithPath: CommandLine.arguments[0]).standardized.path
        return [executablePath]
    }
}
