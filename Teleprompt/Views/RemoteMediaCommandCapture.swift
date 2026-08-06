import MediaPlayer
import SwiftUI
import UIKit

struct RemoteMediaCommandCapture: UIViewRepresentable {
    let onAction: (RemoteAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAction: onAction)
    }

    func makeUIView(context: Context) -> UIView {
        context.coordinator.start()
        return UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onAction = onAction
        context.coordinator.start()
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        var onAction: (RemoteAction) -> Void

        private let center = MPRemoteCommandCenter.shared()
        private var registrations: [(command: MPRemoteCommand, target: Any)] = []
        private var isRunning = false

        init(onAction: @escaping (RemoteAction) -> Void) {
            self.onAction = onAction
        }

        func start() {
            guard !isRunning else { return }
            isRunning = true

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
                // TeleprompterPAD physical X emits Play/Pause on iOS.
                register(center.playCommand, action: .toggleRecordingPause),
                register(center.pauseCommand, action: .toggleRecordingPause),
                register(center.togglePlayPauseCommand, action: .toggleRecordingPause),

                // Physical A emits Fast Forward / Next.
                register(center.nextTrackCommand, action: .playPause),
                register(center.skipForwardCommand, action: .playPause),
                register(center.seekForwardCommand, action: .playPause),

                // Physical B emits Rewind / Previous.
                register(center.previousTrackCommand, action: .toggleControls),
                register(center.skipBackwardCommand, action: .toggleControls),
                register(center.seekBackwardCommand, action: .toggleControls),

                // Physical Y is exposed as Go to top / Stop on supported modes.
                register(center.stopCommand, action: .toggleRecording)
            ]
        }

        func stop() {
            guard isRunning else { return }
            isRunning = false

            for registration in registrations {
                registration.command.removeTarget(registration.target)
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

        private func register(
            _ command: MPRemoteCommand,
            action: RemoteAction
        ) -> (command: MPRemoteCommand, target: Any) {
            let target = command.addTarget { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onAction(action)
                }
                return .success
            }
            return (command, target)
        }
    }
}
