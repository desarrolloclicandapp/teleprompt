import CoreBluetooth
import GameController
import MediaPlayer

@MainActor
final class MediaRemoteController: NSObject, ObservableObject {
    private enum InputSource: String {
        case gameController
        case bluetoothFallback
        case mediaRemote
    }

    var onAction: ((RemoteAction) -> Void)?

    private let center = MPRemoteCommandCenter.shared()
    private let bluetoothFallback = BluetoothGamepadFallbackController()

    private var registered = false
    private var registrations: [(MPRemoteCommand, Any)] = []
    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?
    private var gameControllerConnected = false
    private var activeSource: InputSource = .mediaRemote
    private var nativeDiscoveryStarted = false
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true

        guard !registered else { return }
        registered = true
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
        registrations = [
            (center.playCommand, center.playCommand.addTarget { [weak self] _ in self?.onAction?(.playPause); return .success }),
            (center.pauseCommand, center.pauseCommand.addTarget { [weak self] _ in self?.onAction?(.playPause); return .success }),
            (center.togglePlayPauseCommand, center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.onAction?(.playPause); return .success }),
            (center.nextTrackCommand, center.nextTrackCommand.addTarget { [weak self] _ in self?.onAction?(.next); return .success }),
            (center.previousTrackCommand, center.previousTrackCommand.addTarget { [weak self] _ in self?.onAction?(.previous); return .success }),
            (center.skipForwardCommand, center.skipForwardCommand.addTarget { [weak self] _ in self?.onAction?(.increaseSpeed); return .success }),
            (center.skipBackwardCommand, center.skipBackwardCommand.addTarget { [weak self] _ in self?.onAction?(.decreaseSpeed); return .success })
        ]

        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let controller = notification.object as? GCController else { return }
            Task { @MainActor in
                self.bindNativeController(controller)
            }
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let controller = notification.object as? GCController else { return }
            Task { @MainActor in
                self.unbindNativeController(controller)
            }
        }

        startGameControllerDiscovery()
        refreshGameControllers()
        updateActiveSource()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        if let connectObserver {
            NotificationCenter.default.removeObserver(connectObserver)
            self.connectObserver = nil
        }

        if let disconnectObserver {
            NotificationCenter.default.removeObserver(disconnectObserver)
            self.disconnectObserver = nil
        }

        stopGameControllerDiscovery()
        bluetoothFallback.stop()
        onAction?(.joystick(x: 0, y: 0))

        for (command, target) in registrations {
            command.removeTarget(target)
        }
        registrations.removeAll()
        center.playCommand.isEnabled = false
        center.pauseCommand.isEnabled = false
        center.togglePlayPauseCommand.isEnabled = false
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        registered = false
        activeSource = .mediaRemote
    }

    private func startGameControllerDiscovery() {
        guard !nativeDiscoveryStarted else { return }
        nativeDiscoveryStarted = true
        bluetoothFallback.onAction = { [weak self] action in
            guard let self else { return }
            Task { @MainActor in
                guard self.activeSource != .gameController else { return }
                self.onAction?(action)
            }
        }
        GCController.startWirelessControllerDiscovery { [weak self] in
            Task { @MainActor in
                self?.refreshGameControllers()
            }
        }
    }

    private func stopGameControllerDiscovery() {
        if nativeDiscoveryStarted {
            GCController.stopWirelessControllerDiscovery()
            nativeDiscoveryStarted = false
        }
        let controllers = GCController.controllers()
        for controller in controllers {
            unbindNativeController(controller)
        }
        gameControllerConnected = false
    }

    private func refreshGameControllers() {
        let controllers = GCController.controllers()
        gameControllerConnected = !controllers.isEmpty
        for controller in controllers {
            bindNativeController(controller)
        }
        updateActiveSource()
    }

    private func updateActiveSource() {
        guard isRunning else { return }
        if !gameControllerConnected {
            onAction?(.joystick(x: 0, y: 0))
            activeSource = .bluetoothFallback
            bluetoothFallback.start()
            return
        }

        gameControllerConnected = !GCController.controllers().isEmpty
        if gameControllerConnected {
            activeSource = .gameController
            bluetoothFallback.stop()
        } else {
            activeSource = .bluetoothFallback
            bluetoothFallback.start()
        }
    }

    private func bindNativeController(_ controller: GCController) {
        if let extended = controller.extendedGamepad {
            setupExtendedGamepad(extended)
            activeSource = .gameController
            gameControllerConnected = true
            bluetoothFallback.stop()
            return
        }

        if let micro = controller.microGamepad {
            setupMicroGamepad(micro)
            activeSource = .gameController
            gameControllerConnected = true
            bluetoothFallback.stop()
            return
        }

        if let gamepad = controller.physicalInputProfile as? GCGamepad {
            setupLegacyGamepad(gamepad)
            activeSource = .gameController
            gameControllerConnected = true
            bluetoothFallback.stop()
            return
        }

        updateActiveSource()
    }

    private func unbindNativeController(_ controller: GCController) {
        if let extended = controller.extendedGamepad {
            extended.valueChangedHandler = nil
            extended.leftThumbstick.valueChangedHandler = nil
            extended.rightThumbstick.valueChangedHandler = nil
            extended.buttonA.pressedChangedHandler = nil
            extended.buttonB.pressedChangedHandler = nil
            extended.buttonX.pressedChangedHandler = nil
            extended.buttonY.pressedChangedHandler = nil
            extended.dpad.valueChangedHandler = nil
        }

        if let micro = controller.microGamepad {
            micro.valueChangedHandler = nil
            micro.buttonA.pressedChangedHandler = nil
            micro.buttonX.pressedChangedHandler = nil
            micro.dpad.valueChangedHandler = nil
        }

        if let gamepad = controller.physicalInputProfile as? GCGamepad {
            gamepad.buttonA.pressedChangedHandler = nil
            gamepad.buttonB.pressedChangedHandler = nil
            gamepad.buttonX.pressedChangedHandler = nil
            gamepad.buttonY.pressedChangedHandler = nil
            gamepad.dpad.valueChangedHandler = nil
        }

        if GCController.controllers().isEmpty {
            gameControllerConnected = false
            activeSource = .mediaRemote
            onAction?(.joystick(x: 0, y: 0))
            if isRunning { bluetoothFallback.start() }
        }
    }

    private func setupExtendedGamepad(_ gamepad: GCExtendedGamepad) {
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.onAction?(.playPause)
        }
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.onAction?(.decreaseSpeed)
        }
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.onAction?(.toggleRecordingPause)
        }
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.onAction?(.toggleRecording)
        }
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.handleJoystickInput(Double(xValue), Double(yValue))
        }
        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.handleJoystickInput(Double(xValue), Double(yValue))
        }
        gamepad.dpad.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.handleJoystickInput(Double(xValue), Double(yValue))
        }
    }

    private func setupLegacyGamepad(_ gamepad: GCGamepad) {
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.onAction?(.playPause)
        }
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.onAction?(.decreaseSpeed)
        }
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.onAction?(.toggleRecordingPause)
        }
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.onAction?(.toggleRecording)
        }
        gamepad.dpad.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.handleJoystickInput(Double(xValue), Double(yValue))
        }
    }

    private func setupMicroGamepad(_ gamepad: GCMicroGamepad) {
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.onAction?(.playPause)
        }
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.onAction?(.toggleRecordingPause)
        }
        gamepad.dpad.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.handleJoystickInput(Double(xValue), Double(yValue))
        }
    }

    private func handleJoystickInput(_ rawX: Double, _ rawY: Double) {
        guard activeSource == .gameController else { return }
        let deadZone = 0.08
        let x = abs(rawX) > deadZone ? rawX : 0
        let y = abs(rawY) > deadZone ? rawY : 0
        onAction?(.joystick(x: x, y: y))
    }
}

private final class BluetoothGamepadFallbackController: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var onAction: ((RemoteAction) -> Void)?

    private let serviceUUID = CBUUID(string: "1812")
    private let reportUUID = CBUUID(string: "2A4D")
    private let joystickDeadZone = 0.08
    private let buttonProfileMinimumSamples = 3
    private let buttonProfileMaximumSamples = 5
    private let buttonProfileConfidenceMargin = 2
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var reportCharacteristic: CBCharacteristic?
    private var shouldRun = false
    private var isScanning = false
    private var lastButtons: UInt8 = 0
    private var shouldRetry = true
    private var resolvedButtonProfile: BluetoothButtonProfile?
    private var resolvedDynamicProfile: BluetoothButtonProfileDefinition?
    private var buttonProfileConfidence: [BluetoothButtonProfile: Int] = [.standard: 0, .shifted: 0]
    private var buttonProfileSampleCount = 0
    private var buttonBitFrequency: [UInt8: Int] = [:]

    private enum BluetoothButtonProfile: Int, CaseIterable {
        case standard
        case shifted
    }

    private struct BluetoothButtonProfileDefinition {
        let playPause: UInt8
        let reset: UInt8
        let pauseRecording: UInt8
        let toggleRecording: UInt8

        var mask: UInt8 { playPause | reset | pauseRecording | toggleRecording }
    }

    private var buttonProfiles: [BluetoothButtonProfile: BluetoothButtonProfileDefinition] {
        [
            .standard: .init(playPause: 0x01, reset: 0x02, pauseRecording: 0x04, toggleRecording: 0x08),
            .shifted: .init(playPause: 0x10, reset: 0x20, pauseRecording: 0x40, toggleRecording: 0x80)
        ]
    }

    var running: Bool {
        shouldRun
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func start() {
        shouldRun = true
        guard let central else { return }
        if central.state == .poweredOn {
            startScan()
        } else {
            shouldRetry = true
        }
    }

    func stop() {
        shouldRun = false
        shouldRetry = false
        stopScan()
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        reportCharacteristic = nil
        self.peripheral = nil
        lastButtons = 0
        resolvedButtonProfile = nil
        resolvedDynamicProfile = nil
        buttonProfileConfidence = [.standard: 0, .shifted: 0]
        buttonProfileSampleCount = 0
        buttonBitFrequency.removeAll()
        onAction?(.joystick(x: 0, y: 0))
    }

    private func startScan() {
        guard shouldRun else { return }
        guard !isScanning else { return }
        isScanning = true
        central?.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    private func stopScan() {
        isScanning = false
        central?.stopScan()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard shouldRun else { return }
        if central.state == .poweredOn && shouldRetry {
            startScan()
        } else {
            stopScan()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        guard shouldRun else { return }
        stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard shouldRun else { return }
        if let connectedPeripheral = self.peripheral, connectedPeripheral.identifier == peripheral.identifier {
            reportCharacteristic = nil
            self.peripheral = nil
            lastButtons = 0
            resolvedButtonProfile = nil
            resolvedDynamicProfile = nil
            buttonProfileConfidence = [.standard: 0, .shifted: 0]
            buttonProfileSampleCount = 0
            buttonBitFrequency.removeAll()
            onAction?(.joystick(x: 0, y: 0))
        }
        if shouldRun {
            startScan()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard shouldRun, error == nil else { return }
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == serviceUUID {
            peripheral.discoverCharacteristics([reportUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard shouldRun, error == nil else { return }
        guard service.uuid == serviceUUID else { return }

        for characteristic in service.characteristics ?? [] where characteristic.uuid == reportUUID {
            reportCharacteristic = characteristic
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            peripheral.readValue(for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard shouldRun, error == nil else { return }
        guard characteristic.uuid == reportUUID else { return }
        guard let data = characteristic.value else { return }
        parseAndEmit(data: data)
    }

    private func parseAndEmit(data: Data) {
        let raw = [UInt8](data)
        guard raw.count >= 3 else { return }
        guard let parsed = bestParsedReport(from: raw) else { return }

        let deadzone = joystickDeadZone
        let x = abs(parsed.x) > deadzone ? parsed.x : 0
        let y = abs(parsed.y) > deadzone ? parsed.y : 0
        onAction?(.joystick(x: x, y: y))

        let changed = parsed.buttons ^ lastButtons
        let pressed = parsed.buttons & changed
        emitButtonActions(pressed)

        lastButtons = parsed.buttons
    }

    private func emitButtonActions(_ pressed: UInt8) {
        guard pressed != 0 else { return }

        if resolvedButtonProfile == nil && resolvedDynamicProfile == nil {
            learnButtonProfile(from: pressed)
        }

        guard let profile = resolvedDynamicProfile ?? resolvedButtonProfile.flatMap({ buttonProfiles[$0] }) else { return }

        if (pressed & profile.playPause) != 0 { onAction?(.playPause) }
        if (pressed & profile.reset) != 0 { onAction?(.decreaseSpeed) }
        if (pressed & profile.pauseRecording) != 0 { onAction?(.toggleRecordingPause) }
        if (pressed & profile.toggleRecording) != 0 { onAction?(.toggleRecording) }
    }

    private func learnButtonProfile(from pressed: UInt8) {
        guard pressed != 0 else { return }

        for bit in 0..<8 {
            let mask: UInt8 = UInt8(1 << bit)
            if (pressed & mask) != 0 {
                buttonBitFrequency[mask, default: 0] += 1
            }
        }

        buttonProfileSampleCount += 1
        for profile in BluetoothButtonProfile.allCases {
            if let definition = buttonProfiles[profile] {
                let score = buttonProfileScore(definition, pressed: pressed)
                buttonProfileConfidence[profile, default: 0] += score
            }
        }

        if let resolvedProfile = resolvedStaticButtonProfile() {
            resolvedButtonProfile = resolvedProfile
            resolvedDynamicProfile = nil
            return
        }

        if buttonProfileSampleCount >= buttonProfileMaximumSamples {
            if let fallback = deriveDynamicButtonProfile() {
                resolvedDynamicProfile = fallback
                resolvedButtonProfile = nil
            } else if let fallback = resolvedStaticFallbackProfile() {
                resolvedButtonProfile = fallback
                resolvedDynamicProfile = nil
            }
        }
    }

    private func buttonProfileScore(_ profile: BluetoothButtonProfileDefinition, pressed: UInt8) -> Int {
        let matchingBits = pressed & profile.mask
        let unexpectedBits = pressed & ~profile.mask
        let score = Int(matchingBits.nonzeroBitCount * 3 - unexpectedBits.nonzeroBitCount)
        return max(0, score)
    }

    private func resolvedStaticButtonProfile() -> BluetoothButtonProfile? {
        if buttonProfileSampleCount < buttonProfileMinimumSamples { return nil }

        let ordered = buttonProfileConfidence
            .sorted { left, right in
                if left.value != right.value { return left.value > right.value }
                return left.key.rawValue < right.key.rawValue
            }

        guard let primary = ordered.first else { return nil }
        let secondary = ordered.dropFirst().first?.value ?? Int.min

        if primary.value <= 0 { return nil }
        if buttonProfileSampleCount >= buttonProfileMaximumSamples { return primary.key }

        if primary.value >= secondary + buttonProfileConfidenceMargin {
            return primary.key
        }
        return nil
    }

    private func deriveDynamicButtonProfile() -> BluetoothButtonProfileDefinition? {
        let sortedBits = buttonBitFrequency
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }

        guard sortedBits.count >= 4 else { return nil }
        let bits = sortedBits.prefix(4).map(\.key)
        return BluetoothButtonProfileDefinition(
            playPause: bits[0],
            reset: bits[1],
            pauseRecording: bits[2],
            toggleRecording: bits[3]
        )
    }

    private func resolvedStaticFallbackProfile() -> BluetoothButtonProfile? {
        let ordered = buttonProfileConfidence
            .sorted { left, right in
                if left.value != right.value { return left.value > right.value }
                return left.key.rawValue < right.key.rawValue
            }

        return ordered.first?.value ?? 0 > 0 ? ordered.first?.key : nil
    }

    private func parseReport(buttonByte: UInt8, xByte: UInt8, yByte: UInt8) -> (x: Double, y: Double, buttons: UInt8)? {
        (normalizeAxis(byte: xByte), normalizeAxis(byte: yByte), buttonByte)
    }

    private func bestParsedReport(from raw: [UInt8]) -> (x: Double, y: Double, buttons: UInt8)? {
        let candidates = axisCandidates(from: raw)
        guard !candidates.isEmpty else { return nil }

        guard let best = candidates.max(by: {
            parseConfidence(for: $0, changedButtons: $0.buttons ^ lastButtons) <
            parseConfidence(for: $1, changedButtons: $1.buttons ^ lastButtons)
        }) else { return nil }

        return best
    }

    private func axisCandidates(from raw: [UInt8]) -> [(x: Double, y: Double, buttons: UInt8)] {
        var parsed: [(x: Double, y: Double, buttons: UInt8)] = []
        if raw.count < 3 { return parsed }

        let maxStart = raw.count - 3
        for start in 0...maxStart {
            if let candidate = parseReport(buttonByte: raw[start], xByte: raw[start + 1], yByte: raw[start + 2]) {
                parsed.append(candidate)
            }

            if start + 3 < raw.count,
               let candidate = parseReport(buttonByte: raw[start], xByte: raw[start + 2], yByte: raw[start + 3]) {
                parsed.append(candidate)
            }

            if start + 2 < raw.count {
                if let candidate = parseReport(buttonByte: raw[start + 2], xByte: raw[start], yByte: raw[start + 1]) {
                    parsed.append(candidate)
                }
            }

            if start + 3 < raw.count && start + 4 < raw.count {
                if let candidate = parseReport(
                    buttonByte: raw[start + 1],
                    xByte: raw[start + 2],
                    yByte: raw[start + 3]
                ) {
                    parsed.append(candidate)
                }
            }
        }

        return parsed
    }

    private func parseConfidence(for parsed: (x: Double, y: Double, buttons: UInt8), changedButtons: UInt8) -> Double {
        let joystickMagnitude = abs(parsed.x) + abs(parsed.y)
        let buttonDelta = Double(changedButtons.nonzeroBitCount) * 0.85
        return joystickMagnitude + buttonDelta
    }

    private func normalizeAxis(byte: UInt8) -> Double {
        let centeredByByte = (Double(byte) - 128.0) / 127.0
        let centeredBySigned = Double(Int8(bitPattern: byte)) / 127.0

        if abs(centeredBySigned) <= 1.05 {
            return max(-1.0, min(1.0, centeredBySigned))
        }

        return max(-1.0, min(1.0, centeredByByte))
    }
}
