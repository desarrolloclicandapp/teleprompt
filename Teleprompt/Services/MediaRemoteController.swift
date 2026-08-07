import Combine
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

        registerMediaCommands()
        registerControllerObservers()
        startGameControllerDiscovery()
        refreshGameControllers()
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
        emit(.joystick(x: 0, y: 0))
        unregisterMediaCommands()
        activeSource = .mediaRemote
    }

    private func registerMediaCommands() {
        guard registrations.isEmpty else { return }

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
        center.seekForwardCommand.isEnabled = true
        center.seekBackwardCommand.isEnabled = true
        center.stopCommand.isEnabled = true

        registrations = [
            // RemotePAD iOS teleprompter mode exposes physical X as the
            // system play/pause command.
            register(center.playCommand, action: .toggleRecordingPause),
            register(center.pauseCommand, action: .toggleRecordingPause),
            register(center.togglePlayPauseCommand, action: .toggleRecordingPause),

            // Physical A is fast-forward, B is rewind and Y is go-to-top.
            register(center.nextTrackCommand, action: .playPause),
            register(center.skipForwardCommand, action: .playPause),
            register(center.seekForwardCommand, action: .playPause),
            register(center.previousTrackCommand, action: .toggleControls),
            register(center.skipBackwardCommand, action: .toggleControls),
            register(center.seekBackwardCommand, action: .toggleControls),
            register(center.stopCommand, action: .toggleRecording)
        ]
    }

    private func register(_ command: MPRemoteCommand, action: RemoteAction) -> (MPRemoteCommand, Any) {
        let target = command.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.emit(action)
            }
            return .success
        }
        return (command, target)
    }

    private func unregisterMediaCommands() {
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
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
        center.stopCommand.isEnabled = false
    }

    private func registerControllerObservers() {
        guard connectObserver == nil, disconnectObserver == nil else { return }

        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            Task { @MainActor in
                self?.bindNativeController(controller)
            }
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            Task { @MainActor in
                self?.unbindNativeController(controller)
            }
        }
    }

    private func startGameControllerDiscovery() {
        guard !nativeDiscoveryStarted else { return }
        nativeDiscoveryStarted = true

        bluetoothFallback.onAction = { [weak self] action in
            Task { @MainActor in
                guard let self, self.activeSource != .gameController else { return }
                self.emit(action)
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

        for controller in GCController.controllers() {
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

        gameControllerConnected = !GCController.controllers().isEmpty
        if gameControllerConnected {
            activeSource = .gameController
            bluetoothFallback.stop()
        } else {
            activeSource = .bluetoothFallback
            emit(.joystick(x: 0, y: 0))
            bluetoothFallback.start()
        }
    }

    private func bindNativeController(_ controller: GCController) {
        if let extended = controller.extendedGamepad {
            setupExtendedGamepad(extended)
            gameControllerConnected = true
            activeSource = .gameController
            bluetoothFallback.stop()
            return
        }

        if let micro = controller.microGamepad {
            setupMicroGamepad(micro)
            gameControllerConnected = true
            activeSource = .gameController
            bluetoothFallback.stop()
            return
        }

        if let legacy = controller.physicalInputProfile as? GCGamepad {
            setupLegacyGamepad(legacy)
            gameControllerConnected = true
            activeSource = .gameController
            bluetoothFallback.stop()
            return
        }

        updateActiveSource()
    }

    private func unbindNativeController(_ controller: GCController) {
        if let extended = controller.extendedGamepad {
            extended.leftThumbstick.valueChangedHandler = nil
            extended.rightThumbstick.valueChangedHandler = nil
            extended.dpad.valueChangedHandler = nil
            extended.buttonA.pressedChangedHandler = nil
            extended.buttonB.pressedChangedHandler = nil
            extended.buttonX.pressedChangedHandler = nil
            extended.buttonY.pressedChangedHandler = nil
        }

        if let micro = controller.microGamepad {
            micro.dpad.valueChangedHandler = nil
            micro.buttonA.pressedChangedHandler = nil
            micro.buttonX.pressedChangedHandler = nil
        }

        if let legacy = controller.physicalInputProfile as? GCGamepad {
            legacy.dpad.valueChangedHandler = nil
            legacy.buttonA.pressedChangedHandler = nil
            legacy.buttonB.pressedChangedHandler = nil
            legacy.buttonX.pressedChangedHandler = nil
            legacy.buttonY.pressedChangedHandler = nil
        }

        emit(.joystick(x: 0, y: 0))
        updateActiveSource()
    }

    private func setupExtendedGamepad(_ gamepad: GCExtendedGamepad) {
        bindButton(gamepad.buttonA, action: .playPause)
        bindButton(gamepad.buttonB, action: .toggleControls)
        bindButton(gamepad.buttonX, action: .toggleRecordingPause)
        bindButton(gamepad.buttonY, action: .toggleRecording)

        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.emitJoystick(x: Double(xValue), y: Double(yValue))
        }
        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.emitJoystick(x: Double(xValue), y: Double(yValue))
        }
        gamepad.dpad.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.emitJoystick(x: Double(xValue), y: Double(yValue))
        }
    }

    private func setupLegacyGamepad(_ gamepad: GCGamepad) {
        bindButton(gamepad.buttonA, action: .playPause)
        bindButton(gamepad.buttonB, action: .toggleControls)
        bindButton(gamepad.buttonX, action: .toggleRecordingPause)
        bindButton(gamepad.buttonY, action: .toggleRecording)

        gamepad.dpad.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.emitJoystick(x: Double(xValue), y: Double(yValue))
        }
    }

    private func setupMicroGamepad(_ gamepad: GCMicroGamepad) {
        bindButton(gamepad.buttonA, action: .playPause)
        bindButton(gamepad.buttonX, action: .toggleRecordingPause)

        gamepad.dpad.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.emitJoystick(x: Double(xValue), y: Double(yValue))
        }
    }

    private func bindButton(_ button: GCControllerButtonInput, action: RemoteAction) {
        button.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in
                self?.emit(action)
            }
        }
    }

    private nonisolated func emitJoystick(x rawX: Double, y rawY: Double) {
        Task { @MainActor [weak self] in
            guard let self, self.activeSource == .gameController else { return }
            let deadZone = 0.12
            let x = abs(rawX) > deadZone ? rawX : 0
            let y = abs(rawY) > deadZone ? rawY : 0
            self.emit(.joystick(x: x, y: y))
        }
    }

    private func emit(_ action: RemoteAction) {
        onAction?(action)
    }
}

private final class BluetoothGamepadFallbackController: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var onAction: ((RemoteAction) -> Void)?

    private let hidServiceUUID = CBUUID(string: "1812")
    private let reportUUID = CBUUID(string: "2A4D")
    private let joystickDeadZone = 0.12

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var shouldRun = false
    private var isScanning = false
    private var lastButtons: UInt8 = 0
    private var lastX = 0.0
    private var lastY = 0.0
    private var parserConfiguration: ParserConfiguration?

    private enum AxisEncoding: CaseIterable, Hashable {
        case unsignedCentered
        case signed
    }

    private struct ParserConfiguration: Hashable {
        let buttonIndex: Int
        let xIndex: Int
        let yIndex: Int
        let encoding: AxisEncoding
    }

    private struct ParsedReport {
        let x: Double
        let y: Double
        let buttons: UInt8
        let configuration: ParserConfiguration
        let score: Double
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func start() {
        shouldRun = true
        guard let central else { return }

        guard central.state == .poweredOn else { return }
        connectKnownPeripheralOrScan(using: central)
    }

    func stop() {
        shouldRun = false
        stopScan()

        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }

        self.peripheral = nil
        resetInputState()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard shouldRun else { return }

        if central.state == .poweredOn {
            connectKnownPeripheralOrScan(using: central)
        } else {
            stopScan()
            peripheral = nil
            resetInputState()
        }
    }

    private func connectKnownPeripheralOrScan(using central: CBCentralManager) {
        if let connected = central.retrieveConnectedPeripherals(withServices: [hidServiceUUID]).first {
            attach(to: connected)
            if connected.state == .connected {
                connected.discoverServices([hidServiceUUID])
            } else {
                central.connect(connected, options: nil)
            }
            return
        }

        startScan()
    }

    private func startScan() {
        guard shouldRun, !isScanning else { return }
        isScanning = true
        central?.scanForPeripherals(
            withServices: [hidServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func stopScan() {
        guard isScanning else { return }
        isScanning = false
        central?.stopScan()
    }

    private func attach(to peripheral: CBPeripheral) {
        stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard shouldRun else { return }
        attach(to: peripheral)
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard shouldRun else { return }
        attach(to: peripheral)
        peripheral.discoverServices([hidServiceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard shouldRun else { return }
        self.peripheral = nil
        resetInputState()
        startScan()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard shouldRun else { return }

        if self.peripheral?.identifier == peripheral.identifier {
            self.peripheral = nil
            resetInputState()
        }
        startScan()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard shouldRun, error == nil else { return }

        for service in peripheral.services ?? [] where service.uuid == hidServiceUUID {
            peripheral.discoverCharacteristics([reportUUID], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard shouldRun, error == nil, service.uuid == hidServiceUUID else { return }

        for characteristic in service.characteristics ?? [] where characteristic.uuid == reportUUID {
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard shouldRun, error == nil, characteristic.uuid == reportUUID else { return }
        guard let data = characteristic.value else { return }
        parseAndEmit(data)
    }

    private func parseAndEmit(_ data: Data) {
        let raw = [UInt8](data)
        guard raw.count >= 3 else { return }
        guard let parsed = parseBestReport(raw) else { return }

        // HID axes normally grow downward on Y. GameController grows upward,
        // so invert Y here to present one consistent contract to the view.
        let x = abs(parsed.x) > joystickDeadZone ? parsed.x : 0
        let normalizedY = -parsed.y
        let y = abs(normalizedY) > joystickDeadZone ? normalizedY : 0
        onAction?(.joystick(x: x, y: y))

        let changed = parsed.buttons ^ lastButtons
        let pressed = parsed.buttons & changed
        emitButtonActions(pressed)

        lastButtons = parsed.buttons
        lastX = parsed.x
        lastY = parsed.y
    }

    private func parseBestReport(_ raw: [UInt8]) -> ParsedReport? {
        if let parserConfiguration,
           let parsed = parse(raw, using: parserConfiguration, includeScore: false) {
            return parsed
        }

        let candidates = parserCandidates(for: raw)
            .compactMap { parse(raw, using: $0, includeScore: true) }

        guard let best = candidates.max(by: { $0.score < $1.score }) else { return nil }
        parserConfiguration = best.configuration
        return best
    }

    private func parserCandidates(for raw: [UInt8]) -> [ParserConfiguration] {
        var layouts: [(button: Int, x: Int, y: Int)] = [
            (0, 1, 2),
            (2, 0, 1)
        ]

        if raw.count >= 4 {
            layouts.append((button: 1, x: 2, y: 3))
            layouts.append((button: 3, x: 1, y: 2))
            layouts.append((button: 0, x: 2, y: 3))
        }

        return layouts.flatMap { layout in
            AxisEncoding.allCases.map {
                ParserConfiguration(
                    buttonIndex: layout.button,
                    xIndex: layout.x,
                    yIndex: layout.y,
                    encoding: $0
                )
            }
        }
    }

    private func parse(
        _ raw: [UInt8],
        using configuration: ParserConfiguration,
        includeScore: Bool
    ) -> ParsedReport? {
        let highestIndex = max(configuration.buttonIndex, max(configuration.xIndex, configuration.yIndex))
        guard highestIndex < raw.count else { return nil }

        let buttons = raw[configuration.buttonIndex]
        guard isLikelyButtonByte(buttons) else { return nil }

        let x = normalize(raw[configuration.xIndex], encoding: configuration.encoding)
        let y = normalize(raw[configuration.yIndex], encoding: configuration.encoding)

        let score: Double
        if includeScore {
            let buttonChanges = (buttons ^ lastButtons).nonzeroBitCount
            let buttonContinuity = buttonChanges <= 2 ? 2.0 : -Double(buttonChanges)
            let neutralOrContinuity: Double

            if parserConfiguration == nil {
                neutralOrContinuity = 4.0 - abs(x) - abs(y)
            } else {
                neutralOrContinuity = 4.0 - abs(x - lastX) - abs(y - lastY)
            }

            let conventionalLayoutBonus = configuration.buttonIndex <= 1 ? 0.4 : 0
            score = buttonContinuity + neutralOrContinuity + conventionalLayoutBonus
        } else {
            score = 0
        }

        return ParsedReport(
            x: x,
            y: y,
            buttons: buttons,
            configuration: configuration,
            score: score
        )
    }

    private func normalize(_ byte: UInt8, encoding: AxisEncoding) -> Double {
        let value: Double
        switch encoding {
        case .unsignedCentered:
            value = (Double(byte) - 128.0) / 127.0
        case .signed:
            value = Double(Int8(bitPattern: byte)) / 127.0
        }
        return max(-1, min(1, value))
    }

    private func isLikelyButtonByte(_ value: UInt8) -> Bool {
        value == 0 || value.nonzeroBitCount <= 4
    }

    private func emitButtonActions(_ pressed: UInt8) {
        guard pressed != 0 else { return }

        // Most compact teleprompter pads expose A/B/X/Y either in the low
        // nibble or shifted into the high nibble. Support both deterministically.
        if (pressed & 0x01) != 0 || (pressed & 0x10) != 0 {
            onAction?(.playPause)
        }
        if (pressed & 0x02) != 0 || (pressed & 0x20) != 0 {
            onAction?(.toggleControls)
        }
        if (pressed & 0x04) != 0 || (pressed & 0x40) != 0 {
            onAction?(.toggleRecordingPause)
        }
        if (pressed & 0x08) != 0 || (pressed & 0x80) != 0 {
            onAction?(.toggleRecording)
        }
    }

    private func resetInputState() {
        lastButtons = 0
        lastX = 0
        lastY = 0
        parserConfiguration = nil
        onAction?(.joystick(x: 0, y: 0))
    }
}
