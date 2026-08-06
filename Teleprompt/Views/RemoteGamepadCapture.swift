import GameController
import SwiftUI
import UIKit

struct RemoteGamepadCapture: UIViewRepresentable {
    let onAction: (RemoteAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAction: onAction)
    }

    func makeUIView(context: Context) -> RemoteGamepadHostView {
        let view = RemoteGamepadHostView()
        context.coordinator.start()
        DispatchQueue.main.async {
            view.activateCapture()
        }
        return view
    }

    func updateUIView(_ uiView: RemoteGamepadHostView, context: Context) {
        context.coordinator.onAction = onAction
        context.coordinator.refreshControllers()
        uiView.activateCapture()
    }

    static func dismantleUIView(
        _ uiView: RemoteGamepadHostView,
        coordinator: Coordinator
    ) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        var onAction: (RemoteAction) -> Void

        private enum AxisRole {
            case horizontal
            case vertical
        }

        private final class ControllerBinding {
            let controller: GCController
            var buttonActions: [ObjectIdentifier: RemoteAction] = [:]
            var directionalPads: Set<ObjectIdentifier> = []
            var looseAxisRoles: [ObjectIdentifier: AxisRole] = [:]
            var pressedButtons: Set<ObjectIdentifier> = []
            var looseX = 0.0
            var looseY = 0.0

            init(controller: GCController) {
                self.controller = controller
            }
        }

        private var connectObserver: NSObjectProtocol?
        private var disconnectObserver: NSObjectProtocol?
        private var currentObserver: NSObjectProtocol?
        private var bindings: [ObjectIdentifier: ControllerBinding] = [:]
        private var isRunning = false

        init(onAction: @escaping (RemoteAction) -> Void) {
            self.onAction = onAction
        }

        func start() {
            guard !isRunning else { return }
            isRunning = true

            connectObserver = NotificationCenter.default.addObserver(
                forName: .GCControllerDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let controller = notification.object as? GCController else { return }
                Task { @MainActor [weak self] in
                    self?.bind(controller)
                }
            }

            disconnectObserver = NotificationCenter.default.addObserver(
                forName: .GCControllerDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let controller = notification.object as? GCController else { return }
                Task { @MainActor [weak self] in
                    self?.unbind(controller)
                }
            }

            currentObserver = NotificationCenter.default.addObserver(
                forName: .GCControllerDidBecomeCurrent,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let controller = notification.object as? GCController else { return }
                Task { @MainActor [weak self] in
                    self?.bind(controller)
                }
            }

            GCController.startWirelessControllerDiscovery { [weak self] in
                Task { @MainActor [weak self] in
                    self?.refreshControllers()
                }
            }

            refreshControllers()
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
            if let currentObserver {
                NotificationCenter.default.removeObserver(currentObserver)
                self.currentObserver = nil
            }

            GCController.stopWirelessControllerDiscovery()

            let currentBindings = Array(bindings.values)
            for binding in currentBindings {
                clearHandlers(from: binding.controller)
            }
            bindings.removeAll()
            onAction(.joystick(x: 0, y: 0))
        }

        func refreshControllers() {
            guard isRunning else { return }

            var connected = GCController.controllers()
            if let current = GCController.current,
               !connected.contains(where: { $0 === current }) {
                connected.append(current)
            }

            let connectedIDs = Set(connected.map { ObjectIdentifier($0) })
            let disconnected = bindings.values.filter {
                !connectedIDs.contains(ObjectIdentifier($0.controller))
            }

            for binding in disconnected {
                unbind(binding.controller)
            }
            for controller in connected {
                bind(controller)
            }
        }

        private func bind(_ controller: GCController) {
            guard isRunning else { return }

            let controllerID = ObjectIdentifier(controller)
            guard bindings[controllerID] == nil else { return }

            controller.handlerQueue = .main

            if let micro = controller.microGamepad {
                micro.reportsAbsoluteDpadValues = true
                micro.allowsRotation = false
            }

            let profile = controller.physicalInputProfile
            disableSystemGestures(in: profile)

            let binding = ControllerBinding(controller: controller)
            bindings[controllerID] = binding

            mapStandardControls(controller, into: binding)
            mapNamedFallbackControls(profile, into: binding)
            mapDirectionalInputs(profile, into: binding)
            mapLooseAxes(profile, into: binding)

            profile.valueDidChangeHandler = { [weak self] _, element in
                Task { @MainActor [weak self] in
                    self?.handleChangedElement(element, controllerID: controllerID)
                }
            }

            // Older and generic controllers may expose a Menu/Pause button only
            // through this compatibility callback. Treat it as physical B.
            controller.controllerPausedHandler = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onAction(.toggleControls)
                }
            }

#if DEBUG
            print("[RemotePAD/Game] connected:", controller.vendorName ?? "unknown")
            print("[RemotePAD/Game] all buttons:")
            for button in profile.allButtons {
                print("  -", debugNames(for: button, in: profile).sorted())
            }
            print("[RemotePAD/Game] all dpads:")
            for pad in profile.allDpads {
                print("  -", debugNames(for: pad, in: profile).sorted())
            }
            print("[RemotePAD/Game] all loose axes:")
            for axis in profile.allAxes where axis.collection == nil {
                print("  -", debugNames(for: axis, in: profile).sorted())
            }
#endif
        }

        private func unbind(_ controller: GCController) {
            clearHandlers(from: controller)
            bindings.removeValue(forKey: ObjectIdentifier(controller))
            onAction(.joystick(x: 0, y: 0))
        }

        private func clearHandlers(from controller: GCController) {
            controller.controllerPausedHandler = nil
            controller.physicalInputProfile.valueDidChangeHandler = nil
        }

        private func disableSystemGestures(in profile: GCPhysicalInputProfile) {
            // A and the directional controls are commonly consumed by UIKit's
            // game-controller focus/navigation layer. Request direct delivery
            // for every physical element, including unnamed generic controls.
            for element in profile.allElements {
                element.preferredSystemGestureState = .disabled
            }
            for button in profile.allButtons {
                button.preferredSystemGestureState = .disabled
            }
            for pad in profile.allDpads {
                pad.preferredSystemGestureState = .disabled
                pad.xAxis.preferredSystemGestureState = .disabled
                pad.yAxis.preferredSystemGestureState = .disabled
            }
            for axis in profile.allAxes {
                axis.preferredSystemGestureState = .disabled
            }
        }

        private func mapStandardControls(
            _ controller: GCController,
            into binding: ControllerBinding
        ) {
            if let extended = controller.extendedGamepad {
                assign(extended.buttonA, action: .playPause, to: binding)
                assign(extended.buttonB, action: .toggleControls, to: binding)
                assign(extended.buttonX, action: .toggleRecordingPause, to: binding)
                assign(extended.buttonY, action: .toggleRecording, to: binding)

                register(extended.dpad, asDirectionalPadIn: binding)
                register(extended.leftThumbstick, asDirectionalPadIn: binding)
                register(extended.rightThumbstick, asDirectionalPadIn: binding)
            }

            if let legacy = controller.gamepad {
                assign(legacy.buttonA, action: .playPause, to: binding)
                assign(legacy.buttonB, action: .toggleControls, to: binding)
                assign(legacy.buttonX, action: .toggleRecordingPause, to: binding)
                assign(legacy.buttonY, action: .toggleRecording, to: binding)
                register(legacy.dpad, asDirectionalPadIn: binding)
            }

            if let micro = controller.microGamepad {
                assign(micro.buttonA, action: .playPause, to: binding)
                assign(micro.buttonX, action: .toggleRecordingPause, to: binding)
                register(micro.dpad, asDirectionalPadIn: binding)
            }
        }

        private func mapNamedFallbackControls(
            _ profile: GCPhysicalInputProfile,
            into binding: ControllerBinding
        ) {
            for button in profile.allButtons {
                let id = ObjectIdentifier(button)
                guard binding.buttonActions[id] == nil else { continue }

                let names = debugNames(for: button, in: profile)
                if let action = action(forNames: names) {
                    assign(button, action: action, to: binding)
                }
            }
        }

        private func mapDirectionalInputs(
            _ profile: GCPhysicalInputProfile,
            into binding: ControllerBinding
        ) {
            // allDpads includes directional pads and thumbstick-like directional
            // elements even when the vendor didn't expose a standard dictionary key.
            for pad in profile.allDpads {
                register(pad, asDirectionalPadIn: binding)
            }
        }

        private func mapLooseAxes(
            _ profile: GCPhysicalInputProfile,
            into binding: ControllerBinding
        ) {
            for axis in profile.allAxes {
                // If an axis belongs to a direction pad/thumbstick, the profile
                // change callback reports the containing pad; don't double-bind it.
                guard axis.collection == nil else { continue }
                let names = debugNames(for: axis, in: profile)
                guard let role = axisRole(forNames: names) else { continue }
                binding.looseAxisRoles[ObjectIdentifier(axis)] = role
            }
        }

        private func assign(
            _ button: GCControllerButtonInput,
            action: RemoteAction,
            to binding: ControllerBinding
        ) {
            binding.buttonActions[ObjectIdentifier(button)] = action
            button.preferredSystemGestureState = .disabled
        }

        private func register(
            _ pad: GCControllerDirectionPad,
            asDirectionalPadIn binding: ControllerBinding
        ) {
            binding.directionalPads.insert(ObjectIdentifier(pad))
            pad.preferredSystemGestureState = .disabled
            pad.xAxis.preferredSystemGestureState = .disabled
            pad.yAxis.preferredSystemGestureState = .disabled
        }

        private func handleChangedElement(
            _ element: GCControllerElement,
            controllerID: ObjectIdentifier
        ) {
            guard let binding = bindings[controllerID] else { return }

            if let button = element as? GCControllerButtonInput {
                handleButton(button, binding: binding)
                return
            }

            if let pad = element as? GCControllerDirectionPad {
                let id = ObjectIdentifier(pad)
                guard binding.directionalPads.contains(id) else { return }
                emitDirectionalPad(pad)
                return
            }

            if let axis = element as? GCControllerAxisInput {
                handleLooseAxis(axis, binding: binding)
                return
            }

#if DEBUG
            let profile = binding.controller.physicalInputProfile
            print("[RemotePAD/Game] changed unmapped element:", debugNames(for: element, in: profile))
#endif
        }

        private func handleButton(
            _ button: GCControllerButtonInput,
            binding: ControllerBinding
        ) {
            let id = ObjectIdentifier(button)
            guard let action = binding.buttonActions[id] else {
#if DEBUG
                print(
                    "[RemotePAD/Game] unmapped button event:",
                    debugNames(for: button, in: binding.controller.physicalInputProfile),
                    "pressed:", button.isPressed,
                    "value:", button.value
                )
#endif
                return
            }

            if button.isPressed {
                guard binding.pressedButtons.insert(id).inserted else { return }
                onAction(action)
            } else {
                binding.pressedButtons.remove(id)
            }
        }

        private func emitDirectionalPad(_ pad: GCControllerDirectionPad) {
            let deadZone = 0.08
            let rawX = Double(pad.xAxis.value)
            let rawY = Double(pad.yAxis.value)
            let x = abs(rawX) > deadZone ? rawX : 0
            let y = abs(rawY) > deadZone ? rawY : 0
            onAction(.joystick(x: x, y: y))
        }

        private func handleLooseAxis(
            _ axis: GCControllerAxisInput,
            binding: ControllerBinding
        ) {
            guard let role = binding.looseAxisRoles[ObjectIdentifier(axis)] else { return }
            let deadZone = 0.08
            let value = abs(Double(axis.value)) > deadZone ? Double(axis.value) : 0

            switch role {
            case .horizontal:
                binding.looseX = value
            case .vertical:
                binding.looseY = value
            }

            onAction(.joystick(x: binding.looseX, y: binding.looseY))
        }

        private func action(forNames names: Set<String>) -> RemoteAction? {
            let normalizedNames = names.map(normalize)

            if normalizedNames.contains(where: isButtonAName) {
                return .playPause
            }
            if normalizedNames.contains(where: isButtonBName) {
                return .toggleControls
            }
            if normalizedNames.contains(where: isButtonXName) {
                return .toggleRecordingPause
            }
            if normalizedNames.contains(where: isButtonYName) {
                return .toggleRecording
            }

            // Compatibility for generic remotes that expose their auxiliary
            // buttons as navigation controls instead of A/B/X/Y.
            if normalizedNames.contains(where: {
                $0.contains("menu") || $0.contains("back") || $0.contains("escape")
            }) {
                return .toggleControls
            }
            if normalizedNames.contains(where: { $0.contains("home") }) {
                return .toggleRecording
            }

            return nil
        }

        private func axisRole(forNames names: Set<String>) -> AxisRole? {
            let normalizedNames = names.map(normalize)
            if normalizedNames.contains(where: {
                $0.contains("x axis")
                    || $0.contains("horizontal")
                    || $0.contains("thumbstick x")
                    || $0.hasSuffix(" x")
            }) {
                return .horizontal
            }
            if normalizedNames.contains(where: {
                $0.contains("y axis")
                    || $0.contains("vertical")
                    || $0.contains("thumbstick y")
                    || $0.hasSuffix(" y")
            }) {
                return .vertical
            }
            return nil
        }

        private func isButtonAName(_ name: String) -> Bool {
            name == normalize(GCInputButtonA)
                || name == "a"
                || name == "button a"
                || name.contains("a.circle")
        }

        private func isButtonBName(_ name: String) -> Bool {
            name == normalize(GCInputButtonB)
                || name == "b"
                || name == "button b"
                || name.contains("b.circle")
        }

        private func isButtonXName(_ name: String) -> Bool {
            name == normalize(GCInputButtonX)
                || name == "x"
                || name == "button x"
                || name.contains("x.circle")
        }

        private func isButtonYName(_ name: String) -> Bool {
            name == normalize(GCInputButtonY)
                || name == "y"
                || name == "button y"
                || name.contains("y.circle")
        }

        private func normalize(_ value: String) -> String {
            value
                .lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func debugNames(
            for element: GCControllerElement,
            in profile: GCPhysicalInputProfile
        ) -> Set<String> {
            var names = element.aliases

            for (key, candidate) in profile.elements where candidate === element {
                names.insert(key)
            }
            if let localizedName = element.localizedName {
                names.insert(localizedName)
            }
            if let unmappedLocalizedName = element.unmappedLocalizedName {
                names.insert(unmappedLocalizedName)
            }
            if let symbol = element.sfSymbolsName {
                names.insert(symbol)
            }
            if let unmappedSymbol = element.unmappedSfSymbolsName {
                names.insert(unmappedSymbol)
            }

            return names
        }
    }
}

final class RemoteGamepadHostView: UIView {
    private var eventInteraction: (any UIInteraction)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        activateCapture()
    }

    func activateCapture() {
        // Keyboard-style events must remain owned by RemoteKeyView. This host
        // only requests GameController delivery and never becomes first responder.
        if #available(iOS 26.0, *), eventInteraction == nil {
            let interaction = GCEventInteraction()
            interaction.handledEventTypes = .gamepad
            interaction.receivesEventsInView = false
            addInteraction(interaction)
            eventInteraction = interaction
        }
    }
}
