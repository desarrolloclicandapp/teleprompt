import MediaPlayer

@MainActor
final class MediaRemoteController: ObservableObject {
    var onAction: ((RemoteAction) -> Void)?
    private let center = MPRemoteCommandCenter.shared()
    private var registered = false

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
        center.playCommand.addTarget { [weak self] _ in self?.onAction?(.playPause); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.onAction?(.playPause); return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.onAction?(.playPause); return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.onAction?(.next); return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.onAction?(.previous); return .success }
        center.skipForwardCommand.addTarget { [weak self] _ in self?.onAction?(.increaseSpeed); return .success }
        center.skipBackwardCommand.addTarget { [weak self] _ in self?.onAction?(.decreaseSpeed); return .success }
    }

    func stop() {
        guard registered else { return }
        center.removeTarget(nil)
        registered = false
    }
}

