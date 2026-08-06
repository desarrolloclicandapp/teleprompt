import GameController
import SwiftUI

struct RemoteRawGamepadProbe: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        context.coordinator.start()
        return UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.refresh()
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        private var connectObserver: NSObjectProtocol?
        private var disconnectObserver: NSObjectProtocol?
        private var bound: [ObjectIdentifier: GCController] = [:]

        func start() {
            guard connectObserver == nil else { return }

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

            refresh()
        }

        func refresh() {
            for controller in GCController.controllers() {
                bind(controller)
            }
            if let current = GCController.current {
                bind(current)
            }
        }

        func stop() {
            if let connectObserver {
                NotificationCenter.default.removeObserver(connectObserver)
                self.connectObserver = nil
            }
            if let disconnectObserver {
                NotificationCenter.default.removeObserver(disconnectObserver)
                self.disconnectObserver = nil
            }

            for controller in bound.values {
                clearHandlers(controller)
            }
            bound.removeAll()
        }

        private func bind(_ controller: GCController) {
            let id = ObjectIdentifier(controller)
            guard bound[id] == nil else { return }
            bound[id] = controller

            let profile = controller.physicalInputProfile
            let vendor = controller.vendorName ?? "unknown"
            let category = controller.productCategory
            RemoteInputDiagnostics.shared.log(
                "GC-CONNECT",
                "vendor=\(vendor) category=\(category) buttons=\(profile.allButtons.count) dpads=\(profile.allDpads.count) axes=\(profile.allAxes.count)"
            )

            for button in profile.allButtons {
                let names = namesFor(button, profile: profile)
                button.pressedChangedHandler = { _, value, pressed in
                    Task { @MainActor in
                        RemoteInputDiagnostics.shared.log(
                            "GC-BUTTON",
                            "names=\(names) value=\(String(format: \"%.3f\", value)) pressed=\(pressed)"
                        )
                    }
                }
            }

            for pad in profile.allDpads {
                let names = namesFor(pad, profile: profile)
                pad.valueChangedHandler = { _, x, y in
                    Task { @MainActor in
                        RemoteInputDiagnostics.shared.log(
                            "GC-DPAD",
                            "names=\(names) x=\(String(format: \"%.3f\", x)) y=\(String(format: \"%.3f\", y))"
                        )
                    }
                }
            }

            for axis in profile.allAxes where axis.collection == nil {
                let names = namesFor(axis, profile: profile)
                axis.valueChangedHandler = { _, value in
                    Task { @MainActor in
                        RemoteInputDiagnostics.shared.log(
                            "GC-AXIS",
                            "names=\(names) value=\(String(format: \"%.3f\", value))"
                        )
                    }
                }
            }
        }

        private func unbind(_ controller: GCController) {
            RemoteInputDiagnostics.shared.log(
                "GC-DISCONNECT",
                "vendor=\(controller.vendorName ?? \"unknown\") category=\(controller.productCategory)"
            )
            clearHandlers(controller)
            bound.removeValue(forKey: ObjectIdentifier(controller))
        }

        private func clearHandlers(_ controller: GCController) {
            let profile = controller.physicalInputProfile
            for button in profile.allButtons {
                button.pressedChangedHandler = nil
            }
            for pad in profile.allDpads {
                pad.valueChangedHandler = nil
            }
            for axis in profile.allAxes where axis.collection == nil {
                axis.valueChangedHandler = nil
            }
        }

        private func namesFor(
            _ element: GCControllerElement,
            profile: GCPhysicalInputProfile
        ) -> String {
            let names = profile.elements.compactMap { key, value in
                value === element ? key : nil
            }
            return names.isEmpty ? "<unnamed>" : names.sorted().joined(separator: ",")
        }
    }
}
