import MediaPlayer
import Combine

@MainActor
final class MediaRemoteController: ObservableObject {
    var onAction: ((RemoteAction) -> Void)?
    private let center = MPRemoteCommandCenter.shared()
    private var registered = false
    private var registrations: [(MPRemoteCommand, Any)] = []

    func start() {
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
    }

    func stop() {
        guard registered else { return }
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
    }
}
