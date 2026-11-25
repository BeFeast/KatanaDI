import AppKit
import Foundation

@MainActor
final class MenuBarController: NSObject {
    struct Actions {
        let selectInputChannel: (Int) -> Void
        let selectBufferSize: (Int) -> Void
        let selectOutputMode: (OutputMode) -> Void
        let toggleAutoStart: () -> Void
        let toggleStartAtLogin: () -> Void
        let refreshRoute: () -> Void
        let quit: () -> Void
    }

    private let actions: Actions
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let headlineItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let detailItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let diagnosticsSeparatorItem = NSMenuItem.separator()
    private let diagnosticItems = (0..<4).map { _ in NSMenuItem(title: "", action: nil, keyEquivalent: "") }
    private let controlsSeparatorItem = NSMenuItem.separator()
    private let inputChannelItem = NSMenuItem(title: "Input Channel", action: nil, keyEquivalent: "")
    private let bufferItem = NSMenuItem(title: "Buffer Size", action: nil, keyEquivalent: "")
    private let outputModeItem = NSMenuItem(title: "Output Mode", action: nil, keyEquivalent: "")
    private let autoStartItem = NSMenuItem(title: "Auto Start", action: #selector(handleAutoStartToggle(_:)), keyEquivalent: "")
    private let startAtLoginItem = NSMenuItem(title: "Start at Login", action: #selector(handleStartAtLoginToggle(_:)), keyEquivalent: "")
    private let actionsSeparatorItem = NSMenuItem.separator()
    private let refreshItem = NSMenuItem(title: "Refresh Route", action: #selector(handleRefresh(_:)), keyEquivalent: "")
    private let footerSeparatorItem = NSMenuItem.separator()
    private let quitItem = NSMenuItem(title: "Quit", action: #selector(handleQuit(_:)), keyEquivalent: "q")

    private var status: AppStatus = .waiting("Starting...")
    private var configuration = AppConfiguration.defaults
    private var availableInputChannels: [Int] = Array(1...8)

    init(actions: Actions) {
        self.actions = actions
        super.init()
        configureStatusItem()
        assembleMenu()
        updateMenu()
    }

    func render(status: AppStatus, configuration: AppConfiguration, availableInputChannels: [Int]) {
        self.status = status
        self.configuration = configuration
        self.availableInputChannels = availableInputChannels
        updateStatusButton()
        updateMenu()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.title = ""
        button.imagePosition = .imageOnly
        updateStatusButton()
        statusItem.menu = menu
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else {
            return
        }

        button.toolTip = status.tooltip

        if let image = statusButtonImage(for: status) {
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = status.statusBadge
        }
    }

    private func assembleMenu() {
        headlineItem.isEnabled = false
        detailItem.isEnabled = false
        diagnosticItems.forEach { $0.isEnabled = false }

        autoStartItem.target = self
        startAtLoginItem.target = self
        refreshItem.target = self
        quitItem.target = self

        menu.addItem(headlineItem)
        menu.addItem(detailItem)
        menu.addItem(diagnosticsSeparatorItem)
        for item in diagnosticItems {
            menu.addItem(item)
        }
        menu.addItem(controlsSeparatorItem)
        menu.addItem(inputChannelItem)
        menu.addItem(bufferItem)
        menu.addItem(outputModeItem)
        menu.addItem(autoStartItem)
        menu.addItem(startAtLoginItem)
        menu.addItem(actionsSeparatorItem)
        menu.addItem(refreshItem)
        menu.addItem(footerSeparatorItem)
        menu.addItem(quitItem)
    }

    private func updateMenu() {
        headlineItem.title = status.headline
        detailItem.title = status.detailLine
        updateDiagnosticItems()
        inputChannelItem.submenu = buildInputChannelMenu()
        bufferItem.submenu = buildBufferMenu()
        outputModeItem.submenu = buildOutputModeMenu()
        autoStartItem.state = configuration.autoStart ? .on : .off
        startAtLoginItem.state = configuration.startAtLogin ? .on : .off
    }

    private func updateDiagnosticItems() {
        let diagnosticLines = status.diagnosticLines
        diagnosticsSeparatorItem.isHidden = diagnosticLines.isEmpty

        for (index, item) in diagnosticItems.enumerated() {
            if diagnosticLines.indices.contains(index) {
                item.title = diagnosticLines[index]
                item.isHidden = false
            } else {
                item.title = ""
                item.isHidden = true
            }
        }
    }

    private func buildInputChannelMenu() -> NSMenu {
        let inputChannelMenu = NSMenu()

        for channel in availableInputChannels {
            let item = NSMenuItem(
                title: "Channel \(channel)",
                action: #selector(handleInputChannelSelection(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = channel as NSNumber
            item.state = configuration.inputChannel == channel ? .on : .off
            inputChannelMenu.addItem(item)
        }

        return inputChannelMenu
    }

    private func buildBufferMenu() -> NSMenu {
        let bufferMenu = NSMenu()

        for size in AppConfiguration.supportedBufferSizes {
            let item = NSMenuItem(
                title: "\(size) samples",
                action: #selector(handleBufferSelection(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = size as NSNumber
            item.state = configuration.bufferSize == size ? .on : .off
            bufferMenu.addItem(item)
        }

        return bufferMenu
    }

    private func buildOutputModeMenu() -> NSMenu {
        let outputModeMenu = NSMenu()

        for outputMode in OutputMode.allCases {
            let item = NSMenuItem(
                title: outputMode.menuTitle,
                action: #selector(handleOutputModeSelection(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = outputMode.rawValue as NSString
            item.state = configuration.outputMode == outputMode ? .on : .off
            outputModeMenu.addItem(item)
        }

        return outputModeMenu
    }

    private func statusButtonImage(for status: AppStatus) -> NSImage? {
        let symbolName: String

        switch status {
        case .waiting:
            symbolName = "speaker.wave.2"
        case .active:
            symbolName = "speaker.wave.2.fill"
        case .error:
            symbolName = "exclamationmark.triangle.fill"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "KatanaDI")
        image?.isTemplate = true
        return image
    }

    @objc
    private func handleInputChannelSelection(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? NSNumber else {
            return
        }
        actions.selectInputChannel(value.intValue)
    }

    @objc
    private func handleBufferSelection(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? NSNumber else {
            return
        }
        actions.selectBufferSize(value.intValue)
    }

    @objc
    private func handleOutputModeSelection(_ sender: NSMenuItem) {
        guard
            let value = sender.representedObject as? String,
            let outputMode = OutputMode(rawValue: value)
        else {
            return
        }
        actions.selectOutputMode(outputMode)
    }

    @objc
    private func handleAutoStartToggle(_ sender: NSMenuItem) {
        actions.toggleAutoStart()
    }

    @objc
    private func handleStartAtLoginToggle(_ sender: NSMenuItem) {
        actions.toggleStartAtLogin()
    }

    @objc
    private func handleRefresh(_ sender: NSMenuItem) {
        actions.refreshRoute()
    }

    @objc
    private func handleQuit(_ sender: NSMenuItem) {
        actions.quit()
    }
}
