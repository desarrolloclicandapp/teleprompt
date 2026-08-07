import Foundation
import SwiftUI
import UIKit

extension TeleprompterView {
    func advanceScroll() {
        guard countdownValue == 0 else { return }

        // Generic analog-controller fallback: speed always moves through the
        // same 50 discrete levels used by the RemotePAD and the slider.
        let horizontalInput = abs(joystickInput.x) > 0.12
            ? Double(joystickInput.x)
            : 0
        if horizontalInput != 0 {
            let now = Date()
            if now.timeIntervalSince(lastJoystickSpeedChangeAt) >= 0.08 {
                changeSpeedLevel(by: horizontalInput > 0 ? 1 : -1)
                lastJoystickSpeedChangeAt = now
            }
        } else {
            lastJoystickSpeedChangeAt = .distantPast
        }

        guard maxScrollOffset > 0 else { return }

        // Joystick Y moves the text while automatic playback keeps its current state.
        let verticalInput = abs(joystickInput.y) > 0.12
            ? Double(joystickInput.y)
            : 0
        guard isPlaying || verticalInput != 0 else { return }

        let actualFontSize = panelSize.width > 0
            ? responsiveFontSize(for: panelSize.width)
            : CGFloat(fontSize)
        let fontScale = actualFontSize / referenceFontSize
        let playbackDeltaPerFrame = isPlaying
            ? (speed * 0.12 * Double(fontScale)) / 60.0
            : 0
        let joystickDeltaPerFrame = (
            verticalInput * max(minimumSpeed, speed) * 0.18 * Double(fontScale)
        ) / 60.0

        let requestedOffset = scrollOffset
            + CGFloat(playbackDeltaPerFrame + joystickDeltaPerFrame)
        scrollOffset = min(maxScrollOffset, max(0, requestedOffset))

        // Reaching the end does not change isPlaying. If the user moves back up,
        // automatic playback continues without requiring another Play press.
    }

    func handleRemoteAction(_ action: RemoteAction) {
        guard !recorder.isProcessing else { return }

        if shouldIgnoreDuplicate(action) {
            return
        }

        switch action {
        case .playPause:
            // A: pause/resume text immediately, without a new countdown.
            togglePlaybackFromRemote()

        case .toggleControls:
            // B: hide/show the controls panel.
            withAnimation(.easeInOut(duration: 0.15)) {
                showControls.toggle()
            }

        case .next:
            // Move toward the end of the script in small repeatable steps.
            let step = max(18, viewportHeight * 0.035)
            scrollOffset = min(maxScrollOffset, scrollOffset + step)

        case .previous:
            // Move toward the beginning/top of the script.
            let step = max(18, viewportHeight * 0.035)
            scrollOffset = max(0, scrollOffset - step)

        case .reset:
            resetReader()

        case .increaseSpeed:
            changeSpeedLevel(by: 1)

        case .decreaseSpeed:
            changeSpeedLevel(by: -1)

        case .joystick(let x, let y):
            joystickInput = CGPoint(x: CGFloat(x), y: CGFloat(y))

        case .toggleRecordingPause:
            // X: only pause/resume an existing recording.
            guard recorder.isRecording else { return }
            recorder.togglePauseResume(
                interfaceOrientation: currentInterfaceOrientation
            )

        case .toggleRecording:
            // Y: start a new recording or finalize the current one.
            toggleRecordingFromRemote()
        }
    }

    func changeSpeedLevel(by delta: Int) {
        speed = speedForLevel(speedLevel + delta)
    }

    private func shouldIgnoreDuplicate(_ action: RemoteAction) -> Bool {
        guard let key = discreteActionKey(for: action) else {
            return false
        }

        let now = Date()
        let duplicate = key == lastRemoteActionKey
            && now.timeIntervalSince(lastRemoteActionAt) < 0.18
        lastRemoteActionKey = key
        lastRemoteActionAt = now
        return duplicate
    }

    private func discreteActionKey(for action: RemoteAction) -> String? {
        switch action {
        case .playPause:
            return "playPause"
        case .toggleControls:
            return "toggleControls"
        case .reset:
            return "reset"
        case .toggleRecording:
            return "toggleRecording"
        case .toggleRecordingPause:
            return "toggleRecordingPause"

        // Joystick/finger-repeat actions must not be deduplicated. Holding a
        // direction should continue moving the text or changing its speed.
        case .next, .previous, .increaseSpeed, .decreaseSpeed, .joystick:
            return nil
        }
    }

    func toggleRecordingFromRemote() {
        Task { @MainActor in
            guard !recorder.isProcessing else { return }

            if recorder.isRecording {
                await recorder.stopRecordingSessionAndWait()
                return
            }

            await recorder.prepare()
            guard recorder.isReady else { return }

            showCamera = true
            recorder.toggleRecording(
                interfaceOrientation: currentInterfaceOrientation
            )
        }
    }

    func resetReader() {
        cancelCountdown()
        isPlaying = false
        scrollOffset = 0
    }

    func toggleCamera() {
        guard !recorder.isProcessing else { return }

        if showCamera {
            showCamera = false
            Task {
                await recorder.stopRecordingSessionAndWait()
                recorder.stopSession()
            }
        } else {
            showCamera = true
        }
    }

    func togglePlaybackFromRemote() {
        cancelCountdown()

        if isPlaying {
            isPlaying = false
            return
        }

        if scrollOffset >= maxScrollOffset - 0.5 {
            scrollOffset = 0
        }
        isPlaying = true
    }

    func togglePlayback() {
        if isPlaying {
            isPlaying = false
            cancelCountdown()
            return
        }

        if countdownValue > 0 {
            cancelCountdown()
            return
        }

        if scrollOffset >= maxScrollOffset - 0.5 {
            scrollOffset = 0
        }
        beginCountdown()
    }

    func beginCountdown() {
        cancelCountdown()

        let generation = UUID()
        countdownGeneration = generation
        countdownValue = 3

        countdownTask = Task { @MainActor in
            for value in stride(from: 3, through: 1, by: -1) {
                guard !Task.isCancelled,
                      countdownGeneration == generation else {
                    return
                }
                countdownValue = value
                try? await Task.sleep(for: .seconds(1))
            }

            guard !Task.isCancelled,
                  countdownGeneration == generation else {
                return
            }
            countdownValue = 0
            isPlaying = true
            countdownTask = nil
        }
    }

    func cancelCountdown() {
        countdownGeneration = UUID()
        countdownTask?.cancel()
        countdownTask = nil
        countdownValue = 0
    }
}
