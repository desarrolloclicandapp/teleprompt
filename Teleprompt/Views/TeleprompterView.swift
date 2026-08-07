import Foundation
import SwiftUI
import UIKit

struct TeleprompterView: View {
    @Environment(\.dismiss) var dismiss
    let script: Script

    @StateObject var recorder = CameraRecorder()
    @StateObject var mediaRemote = MediaRemoteController()
    @State var joystickInput: CGPoint = .zero
    @State var lastRemoteActionKey: String?
    @State var lastRemoteActionAt = Date.distantPast
    @State var lastJoystickSpeedChangeAt = Date.distantPast
    @State var isPlaying = false
    @State var speed: Double = 200
    @State var fontSize: Double = 26
    @State var mirrorHorizontal = false
    @State var mirrorVertical = false
    @State var scrollOffset: CGFloat = 0
    @State var contentHeight: CGFloat = 0
    @State var viewportHeight: CGFloat = 0
    @State var countdownValue = 0
    @State var countdownTask: Task<Void, Never>?
    @State var countdownGeneration = UUID()
    @State var showControls = true
    @State var showCamera = false
    @State var showReaderSettings = false
    @State var panelSize: CGSize = .zero
    @State var panelCenter: CGPoint = .zero
    @State var canvasSize: CGSize = .zero
    @State var layoutIsLandscape = false
    @State var panelDragStart: CGPoint?
    @State var resizeStartSize: CGSize?
    @State var textDragStartOffset: CGFloat?
    @State var cameraSideIsTrailing = true

    let minimumSpeed = 200.0
    let maximumSpeed = 1500.0
    let speedLevelCount = 50
    let referenceFontSize: CGFloat = 42
    let portraitControlHeight: CGFloat = 228

    var speedLevelStep: Double {
        (maximumSpeed - minimumSpeed) / Double(speedLevelCount - 1)
    }

    var speedLevel: Int {
        nearestSpeedLevel(for: speed)
    }

    func nearestSpeedLevel(for value: Double) -> Int {
        let index = Int(((value - minimumSpeed) / speedLevelStep).rounded())
        return min(speedLevelCount, max(1, index + 1))
    }

    func speedForLevel(_ level: Int) -> Double {
        let clampedLevel = min(speedLevelCount, max(1, level))
        return (
            minimumSpeed
            + Double(clampedLevel - 1) * speedLevelStep
        ).rounded()
    }

    var maxScrollOffset: CGFloat {
        max(0, contentHeight - viewportHeight)
    }

    var progress: Double {
        guard maxScrollOffset > 0 else { return 0 }
        return min(1, max(0, Double(scrollOffset / maxScrollOffset)))
    }

    var isLandscape: Bool {
        canvasSize.width > canvasSize.height
    }

    var landscapeControlSide: CGFloat {
        min(360, max(280, canvasSize.height - 24))
    }

    var currentInterfaceOrientation: UIInterfaceOrientation {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .interfaceOrientation ?? .portrait
    }
}
