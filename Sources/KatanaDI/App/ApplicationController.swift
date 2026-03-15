import AppKit
import Foundation

@MainActor
final class ApplicationController {
    private let configurationStore = ConfigurationStore()
    private let launchAtLoginController = LaunchAtLoginController()
    private let microphonePermissionController = MicrophonePermissionController()
    private let deviceMonitor = AudioDeviceMonitor()
    private let audioEngine = AudioRoutingEngine()

    private lazy var menuBarController: MenuBarController = {
        MenuBarController(
            actions: .init(
                selectInputChannel: { [weak self] channel in
                    self?.setInputChannel(channel)
                },
                selectBufferSize: { [weak self] bufferSize in
                    self?.setBufferSize(bufferSize)
                },
                selectOutputMode: { [weak self] outputMode in
                    self?.setOutputMode(outputMode)
                },
                toggleAutoStart: { [weak self] in
                    self?.toggleAutoStart()
                },
                toggleStartAtLogin: { [weak self] in
                    self?.toggleStartAtLogin()
                },
                refreshRoute: { [weak self] in
                    self?.refreshRoute()
                },
                quit: {
                    NSApplication.shared.terminate(nil)
                }
            )
        )
    }()
    private var configuration: AppConfiguration
    private var availableInputChannels: [Int] = Array(1...8)
    private var currentInputDevice: AudioDeviceDescriptor?
    private var servicesStarted = false
    private var currentRouteRuntime: RouteRuntimeState?
    private var diagnosticsTimer: Timer?

    init() {
        configuration = (try? configurationStore.load()) ?? .defaults
    }

    func start() {
        updateUI(status: .waiting("Checking microphone access..."))
        ensureMicrophoneAccessAndStart()
    }

    func stop() {
        stopDiagnosticsPolling()
        currentRouteRuntime = nil
        audioEngine.stop()
        if servicesStarted {
            deviceMonitor.stop()
            servicesStarted = false
        }
    }

    private func ensureMicrophoneAccessAndStart() {
        switch microphonePermissionController.status {
        case .authorized:
            startServicesIfNeeded()
            refreshRoute()
        case .notDetermined:
            updateUI(status: .waiting("Requesting microphone access..."))
            microphonePermissionController.requestAccess { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    if granted {
                        self.startServicesIfNeeded()
                        self.refreshRoute()
                    } else {
                        self.applyStatus(.error("Microphone access is required. Enable KatanaDI in System Settings -> Privacy & Security -> Microphone."))
                    }
                }
            }
        case .denied, .restricted:
            applyStatus(.error("Microphone access is required. Enable KatanaDI in System Settings -> Privacy & Security -> Microphone."))
        }
    }

    private func startServicesIfNeeded() {
        guard servicesStarted == false else {
            return
        }

        do {
            try configurationStore.save(configuration)
        } catch {
            Log.app.error("Failed to persist initial configuration: \(error.localizedDescription, privacy: .public)")
        }

        do {
            try launchAtLoginController.sync(enabled: configuration.startAtLogin)
        } catch {
            Log.app.error("Failed to sync launch-at-login state: \(error.localizedDescription, privacy: .public)")
        }

        deviceMonitor.onDevicesChanged = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshRoute()
            }
        }

        do {
            try deviceMonitor.start()
        } catch {
            applyStatus(.error("Failed to start device monitoring: \(error.localizedDescription)"))
            return
        }
        servicesStarted = true
    }

    private func refreshRoute() {
        guard servicesStarted else {
            ensureMicrophoneAccessAndStart()
            return
        }

        switch microphonePermissionController.status {
        case .authorized:
            break
        case .notDetermined:
            applyStatus(.waiting("Requesting microphone access..."))
            ensureMicrophoneAccessAndStart()
            return
        case .denied, .restricted:
            audioEngine.stop()
            applyStatus(.error("Microphone access is required. Enable KatanaDI in System Settings -> Privacy & Security -> Microphone."))
            return
        }

        do {
            let inventory = try deviceMonitor.currentInventory()
            currentInputDevice = inventory.firstInputDevice(matching: configuration.inputDeviceQuery)
            availableInputChannels = currentInputDevice.map { Array(1...max($0.inputChannelCount, 1)) } ?? Array(1...8)

            guard configuration.autoStart else {
                audioEngine.stop()
                applyStatus(.waiting("Auto-start disabled"))
                return
            }

            guard let outputDevice = inventory.firstOutputDevice(matching: configuration.outputDeviceQuery) else {
                audioEngine.stop()
                applyStatus(.error("Built-in Output not available"))
                return
            }

            guard let inputDevice = currentInputDevice else {
                audioEngine.stop()
                applyStatus(.waiting("Waiting for KATANA..."))
                return
            }

            guard configuration.inputChannel <= inputDevice.inputChannelCount else {
                audioEngine.stop()
                applyStatus(.error("Configured input channel \(configuration.inputChannel) is unavailable on \(inputDevice.name)"))
                return
            }

            let runtime = try audioEngine.startOrUpdate(
                inputDevice: inputDevice,
                outputDevice: outputDevice,
                configuration: configuration
            )
            currentRouteRuntime = runtime
            startDiagnosticsPolling()
            refreshDiagnosticsUI()
        } catch {
            audioEngine.stop()
            applyStatus(.error(error.localizedDescription))
        }
    }

    private func applyStatus(_ status: AppStatus) {
        switch status {
        case .active(let runtime):
            currentRouteRuntime = runtime
            startDiagnosticsPolling()
        case .waiting, .error:
            currentRouteRuntime = nil
            stopDiagnosticsPolling()
        }
        updateUI(status: status)
    }

    private func updateUI(status: AppStatus) {
        menuBarController.render(
            status: status,
            configuration: configuration,
            availableInputChannels: availableInputChannels
        )
    }

    private func startDiagnosticsPolling() {
        guard diagnosticsTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDiagnosticsUI()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        diagnosticsTimer = timer
    }

    private func stopDiagnosticsPolling() {
        diagnosticsTimer?.invalidate()
        diagnosticsTimer = nil
    }

    private func refreshDiagnosticsUI() {
        guard let runtime = currentRouteRuntime else {
            return
        }

        let enrichedRuntime = runtime.withDiagnostics(audioEngine.diagnosticsSnapshot())
        updateUI(status: .active(enrichedRuntime))
    }

    private func persistConfiguration() {
        do {
            try configurationStore.save(configuration)
        } catch {
            Log.app.error("Failed to save configuration: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func setInputChannel(_ channel: Int) {
        configuration.inputChannel = channel
        persistConfiguration()
        refreshRoute()
    }

    private func setBufferSize(_ bufferSize: Int) {
        configuration.bufferSize = bufferSize
        persistConfiguration()
        refreshRoute()
    }

    private func setOutputMode(_ outputMode: OutputMode) {
        configuration.outputMode = outputMode
        persistConfiguration()
        refreshRoute()
    }

    private func toggleAutoStart() {
        configuration.autoStart.toggle()
        persistConfiguration()
        refreshRoute()
    }

    private func toggleStartAtLogin() {
        configuration.startAtLogin.toggle()
        persistConfiguration()
        do {
            try launchAtLoginController.sync(enabled: configuration.startAtLogin)
        } catch {
            Log.app.error("Failed to change launch-at-login: \(error.localizedDescription, privacy: .public)")
            configuration.startAtLogin.toggle()
            persistConfiguration()
        }

        refreshRoute()
    }
}
