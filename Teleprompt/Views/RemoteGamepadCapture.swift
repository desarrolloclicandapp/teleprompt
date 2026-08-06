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

        private var connectObserver: NSObjectProtocol?
        private var disconnectObserver: NSObjectProtocol?
        private var boundControllers: [ObjectIdentifier: GCController] = [:]
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

            GCController.stopWirelessControllerDiscovery()

            for controller in boundControllers.values {
                clearHandlers(from: controller)
            }
            boundControllers.removeAll()
            onAction(.joystick(x: 0, y: 0))
        }

        func refreshControllers() {
            guard isRunning else { return }

            let connected = GCController.controllers()
            let connectedIDs = Set(connected.map(ObjectIdentifier.init))

            for controller in boundControllers.values
            where !connectedIDs.contains(ObjectIdentifier(controller)) {
                unbind(controller)
            }

            for controller in connected {
                bind(controller)
            }
        }

        private func bind(_ controller: GCController) {
            guard isRunning else { return }

            let identifier = ObjectIdentifier(controller)
            guard boundControllers[identifier] == nil else { return }

            controller.handlerQueue = .main

            if let micro = controller.microGamepad {
                // Generic RemotePAD devices frequently expose their joystick as
                // a micro-gamepad d-pad. Absolute values make the physical
                // center the neutral point instead of the first touched point.
                micro.reportsAbsoluteDpadValues = true
                micro.allowsRotation = false
            }

            bindButtons(in: controller.physicalInputProfile)
            bindDirectionalInputs(in: controller.physicalInputProfile)

            // Some inexpensive pads expose physical B as the controller Menu
            // button. Capture that button as B instead of allowing navigation.
            controller.controllerPausedHandler = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onAction(.toggleControls)
                }
            }

            boundControllers[identifier] = controller

#if DEBUG
            let profile = controller.physicalInputProfile
            print("[RemotePAD/Game] connected:", controller.vendorName ?? "unknown")
            print("[RemotePAD/Game] buttons:", profile.buttons.keys.sorted())
            print("[RemotePAD/Game] dpads:", profile.dpads.keys.sorted())
#endif
        }

        private func unbind(_ controller: GCController) {
            clearHandlers(from: controller)
            boundControllers.removeValue(forKey: ObjectIdentifier(controller))
            onAction(.joystick(x: 0, y: 0))
        }

        private func clearHandlers(from controller: GCController) {
            controller.controllerPausedHandler = nil

            let profile = controller.physicalInputProfile
            var seenButtons = Set<ObjectIdentifier>()
            for button in profile.buttons.values {
                guard seenButtons.insert(ObjectIdentifier(button)).inserted else { continue }
                button.pressedChangedHandler = nil
            }

            var seenPads = Set<ObjectIdentifier>()
            for pad in profile.dpads.values {
                guard seenPads.insert(ObjectIdentifier(pad)).inserted else { continue }
                pad.valueChangedHandler = nil
            }
        }

        private func bindButtons(in profile: GCPhysicalInputProfile) {
            var seenButtons = Set<ObjectIdentifier>()

            for (name, button) in profile.buttons {
                guard seenButtons.insert(ObjectIdentifier(button)).inserted else { continue }
                guard let action = action(forButtonNamed: name) else {
#if DEBUG
                    print("[RemotePAD/Game] unmapped button:", name)
#endif
                    continue
                }

                button.pressedChangedHandler = { [weak self] _, _, pressed in
                    guard pressed else { return }
                    Task { @MainActor [weak self] in
                        self?.onAction(action)
                    }
                }
            }
        }

        private func bindDirectionalInputs(in profile: GCPhysicalInputProfile) {
            var seenPads = Set<ObjectIdentifier>()

            for (_, pad) in profile.dpads {
                guard seenPads.insert(ObjectIdentifier(pad)).inserted else { continue }

                pad.valueChangedHandler = { [weak self] _, xValue, yValue in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let deadZone = 0.10
                        let x = abs(Double(xValue)) > deadZone ? Double(xValue) : 0
                        let y = abs(Double(yValue)) > deadZone ? Double(yValue) : 0
                        self.onAction(.joystick(x: x, y: y))
                    }
                }
            }
        }

        private func action(forButtonNamed name: String) -> RemoteAction? {
            switch name {
            case GCInputButtonA:
                return .playPause
            case GCInputButtonB, GCInputButtonMenu:
                return .toggleControls
            case GCInputButtonX:
                return .toggleRecordingPause
            case GCInputButtonY, GCInputButtonHome:
                return .toggleRecording
            case GCInputButtonOptions:
                return .playPause
            default:
                break
            }

            let normalized = name
                .lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")

            if normalized == "a" || normalized.contains("button a") {
                return .playPause
            }
            if normalized == "b"
                || normalized.contains("button b")
                || normalized.contains("menu")
                || normalized.contains("back")
                || normalized.contains("escape") {
                return .toggleControls
            }
            if normalized == "x" || normalized.contains("button x") {
                return .toggleRecordingPause
            }
            if normalized == "y"
                || normalized.contains("button y")
                || normalized.contains("home") {
                return .toggleRecording
            }
            if normalized.contains("option") || normalized.contains("start") {
                return .playPause
            }

            return nil
        }
    }
}

final class RemoteGamepadHostView: UIView {
    private var eventInteraction: UIInteraction?

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        activateCapture()
    }

    func activateCapture() {
        if !isFirstResponder {
            becomeFirstResponder()
        }

        // On current iOS versions, request exclusive GameController delivery so
        // B/Menu doesn't become a UIKit "back" navigation event.
        if #available(iOS 26.0, *), eventInteraction == nil {
            let interaction = GCEventInteraction()
            interaction.handledEventTypes = .gamepad
            interaction.receivesEventsInView = false
            addInteraction(interaction)
            eventInteraction = interaction
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()

        for press in presses {
            guard let code = press.key?.keyCode else {
                unhandled.insert(press)
                continue
            }

            // Consume Escape/B-like navigation presses. The corresponding
            // GameController button handler performs the requested B action.
            if code == .keyboardEscape {
                continue
            }

            unhandled.insert(press)
        }

        if !unhandled.isEmpty {
            super.pressesBegan(unhandled, with: event)
        }
    }
}
