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

            let controllers = Array(boundControllers.values)
            for controller in controllers {
                clearHandlers(from: controller)
            }
            boundControllers.removeAll()
            onAction(.joystick(x: 0, y: 0))
        }

        func refreshControllers() {
            guard isRunning else { return }

            let connected = GCController.controllers()
            let connectedIDs = Set(connected.map { ObjectIdentifier($0) })
            let disconnected = boundControllers.values.filter {
                !connectedIDs.contains(ObjectIdentifier($0))
            }

            for controller in disconnected {
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
                micro.reportsAbsoluteDpadValues = true
                micro.allowsRotation = false
            }

            let profile = controller.physicalInputProfile
            bindButtons(in: profile)
            bindDirectionalInputs(in: profile)

            controller.controllerPausedHandler = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onAction(.toggleControls)
                }
            }

            boundControllers[identifier] = controller

#if DEBUG
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

            for pad in profile.dpads.values {
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
    private var eventInteraction: (any UIInteraction)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        activateCapture()
    }

    func activateCapture() {
        // This view deliberately never becomes first responder. Keyboard-style
        // events from TeleprompterPAD must remain owned by RemoteKeyView.
        if #available(iOS 26.0, *), eventInteraction == nil {
            let interaction = GCEventInteraction()
            interaction.handledEventTypes = .gamepad
            interaction.receivesEventsInView = false
            addInteraction(interaction)
            eventInteraction = interaction
        }
    }
}
