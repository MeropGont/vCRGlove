import SwiftUI
import AVFoundation

struct MovementDemonstrationClip: Hashable {
    let fileName: String

    static func clip(task: MovementTaskType, side: BodySide) -> Self? {
        switch task {
        case .fingerTap: return .init(fileName: "finger_tapping_\(side.rawValue)")
        case .handOpenClose:
            // Match the patient's camera-facing view; tapping clips keep their mapping.
            return .init(fileName: "fist_\(side == .left ? "right" : "left")")
        case .pronationSupination: return nil
        }
    }

    var url: URL? {
        Bundle.main.url(forResource: fileName, withExtension: "mp4", subdirectory: "hand_videos")
    }

    static let aspectRatio: CGFloat = 854.0 / 480.0

    var presentationAspectRatio: CGFloat {
        fileName.hasPrefix("fist_") ? 480.0 / 560.0 : Self.aspectRatio
    }

    var maximumWidth: CGFloat { fileName.hasPrefix("fist_") ? 170 : 280 }
    var cropsVerticalMargins: Bool { fileName.hasPrefix("fist_") }
}

@MainActor
final class MovementDemonstrationPlayer: ObservableObject {
    @Published private(set) var player: AVQueuePlayer?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = true
    @Published private(set) var hasFailed = false
    @Published private(set) var elapsed = 0.0

    private var looper: AVPlayerLooper?
    private var timeObserver: Any?
    private var resumesAfterInterruption = false

    func load(url: URL?, automaticallyPlays: Bool) async {
        stop()
        isLoading = true
        hasFailed = false
        guard let url else { fail(); return }
        do {
            let asset = AVURLAsset(url: url)
            guard try await asset.load(.isPlayable), !Task.isCancelled else {
                if !Task.isCancelled { fail() }
                return
            }
            let queue = AVQueuePlayer()
            queue.isMuted = true
            looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(asset: asset))
            player = queue
            timeObserver = queue.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
            ) { [weak self, weak queue] time in
                Task { @MainActor in
                    guard let self, let queue, self.player === queue else { return }
                    if queue.status == .failed || queue.currentItem?.status == .failed {
                        self.fail()
                        return
                    }
                    self.elapsed = time.seconds.isFinite ? max(0, time.seconds) : 0
                }
            }
            // The looper installs its first item asynchronously. Keep the loading state
            // until a frame can be displayed rather than exposing an empty player.
            for _ in 0..<100 where queue.currentItem?.status != .readyToPlay {
                try await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, player === queue else { return }
                if queue.status == .failed || queue.currentItem?.status == .failed { break }
            }
            guard player === queue, !Task.isCancelled else { return }
            guard queue.currentItem?.status == .readyToPlay else { fail(); return }
            isLoading = false
            if automaticallyPlays { play() }
        } catch {
            if !Task.isCancelled { fail() }
        }
    }

    func play() {
        guard let player, !hasFailed else { return }
        player.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func suspend() {
        resumesAfterInterruption = resumesAfterInterruption || isPlaying
        pause()
    }

    func resume() {
        if resumesAfterInterruption { play() }
        resumesAfterInterruption = false
    }

    func stop() {
        pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()
        player = nil
        elapsed = 0
        resumesAfterInterruption = false
    }

    private func fail() {
        stop()
        isLoading = false
        hasFailed = true
    }
}

struct MovementDemonstrationView: View {
    let taskType: MovementTaskType
    let side: BodySide
    var automaticallyPlays = false
    var allowsPlayback = true

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playback = MovementDemonstrationPlayer()

    private var clip: MovementDemonstrationClip? {
        MovementDemonstrationClip.clip(task: taskType, side: side)
    }

    var body: some View {
        if let clip {
            VStack(spacing: 4) {
                ZStack {
                    DemonstrationPlayerSurface(player: playback.player, cropsVerticalMargins: clip.cropsVerticalMargins)
                        .accessibilityLabel("\(L10n("Demonstration")): \(taskType.displayName), \(side.displayName)")
                        .accessibilityValue(String(format: L10n("%.1f seconds"), playback.elapsed))
                        .accessibilityIdentifier("movementDemonstration-\(clip.fileName)")
                    if playback.isLoading {
                        ProgressView()
                    } else if playback.hasFailed {
                        Label(L10n("Video unavailable"), systemImage: "video.slash")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .padding()
                    } else {
                        Button {
                            if playback.isPlaying { playback.pause() }
                            else { playback.play() }
                        } label: {
                            Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 44))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white.opacity(0.85), Color.black.opacity(0.5))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!allowsPlayback)
                        .accessibilityLabel(L10n(playback.isPlaying ? "Pause demonstration" : "Play demonstration"))
                        .accessibilityIdentifier("movementDemonstrationToggle")
                    }
                }
                .aspectRatio(clip.presentationAspectRatio, contentMode: .fit)
                .frame(maxWidth: clip.maximumWidth)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(L10n("Demonstration"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("movementDemonstrationPanel-\(clip.fileName)")
            .task(id: clip) {
                await playback.load(url: clip.url, automaticallyPlays: automaticallyPlays && allowsPlayback)
                if scenePhase != .active { playback.suspend() }
            }
            .onChange(of: allowsPlayback) { _, allowed in
                if !allowed { playback.pause() }
                else if automaticallyPlays && scenePhase == .active { playback.play() }
            }
            .onChange(of: automaticallyPlays) { _, automatic in
                if automatic && allowsPlayback && scenePhase == .active { playback.play() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && allowsPlayback { playback.resume() }
                else { playback.suspend() }
            }
            .onDisappear { playback.stop() }
        }
    }
}

private struct DemonstrationPlayerSurface: UIViewRepresentable {
    let player: AVPlayer?
    let cropsVerticalMargins: Bool

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.isAccessibilityElement = true
        view.clipsToBounds = true
        view.playerLayer.videoGravity = cropsVerticalMargins ? .resizeAspectFill : .resizeAspect
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.playerLayer.videoGravity = cropsVerticalMargins ? .resizeAspectFill : .resizeAspect
        view.playerLayer.player = player
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.playerLayer.player = nil
    }
}
