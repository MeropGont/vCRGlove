//
//  MovementExportView.swift
//  vCRGlove
//
//  Clinic-facing export screen for movement task sessions (Task F).
//  Writes JSON / CSV files to Documents/vcr/tasks/exports/ (reachable via the
//  Files app) and offers immediate sharing via ShareLink (AirDrop, Mail, …).
//

import SwiftUI
import AVKit

struct MovementExportView: View {
    @ObservedObject private var store = TaskSessionStore.shared

    @State private var lastExport: URL?
    @State private var errorMessage: String?
    @State private var selection = Set<UUID>()
    @State private var isSelecting = false
    @State private var confirmingDeletion = false
    @State private var isDeleting = false
    @State private var message: String?

    private var trialCount: Int { store.sessions.reduce(0) { $0 + $1.trials.count } }
    private var videos: [Trial] {
        var seen = Set<UUID>()
        return store.sessions.flatMap(\.trials).filter { $0.video != nil && seen.insert($0.id).inserted }
            .sorted { $0.startedAt > $1.startedAt }
    }
    private var selectedURLs: [URL] {
        (try? store.videoStore.shareURLs(for: videos.filter { selection.contains($0.id) })) ?? []
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(L10n("Sessions"), value: "\(store.sessions.count)")
                LabeledContent(L10n("Trials"), value: "\(trialCount)")
            } header: {
                Text(L10n("Recorded data"))
            }

            videoSection

            Section {
                exportButton(L10n("JSON (full sessions)"), systemImage: "doc.badge.gearshape") {
                    try TaskSessionExporter.exportJSON(store.sessions)
                }
                exportButton(L10n("CSV — metrics per trial"), systemImage: "tablecells") {
                    try TaskSessionExporter.exportMetricsCSV(store.sessions)
                }
                exportButton(L10n("CSV — raw samples"), systemImage: "waveform.path") {
                    try TaskSessionExporter.exportSamplesCSV(store.sessions)
                }
            } header: {
                Text(L10n("Export"))
            } footer: {
                Text(L10n("Files are saved to vcr/tasks/exports and can also be accessed from the Files app."))
            }

            if let url = lastExport {
                Section(L10n("Last export")) {
                    LabeledContent(L10n("File"), value: url.lastPathComponent)
                    ShareLink(item: url) {
                        Label(L10n("Share…"), systemImage: "square.and.arrow.up")
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(L10n(errorMessage))
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(L10n("Data"))
        .toolbar {
            if isSelecting {
                ToolbarItem(id: "shareSelectedVideos", placement: .topBarTrailing) {
                    ShareLink(items: selectedURLs) { Image(systemName: "square.and.arrow.up") }
                        .disabled(selection.isEmpty || selectedURLs.count != selection.count || isDeleting)
                        .accessibilityLabel(L10n("Share videos"))
                        .accessibilityIdentifier("movementShareVideos")
                }
                ToolbarItem(id: "deleteSelectedVideos", placement: .topBarTrailing) {
                    Button(role: .destructive) { confirmingDeletion = true } label: {
                        if isDeleting { ProgressView() }
                        else { Image(systemName: "trash") }
                    }
                    .disabled(selection.isEmpty || isDeleting)
                    .accessibilityLabel(String(format: L10n("Delete selected videos (%d)"), selection.count))
                    .accessibilityIdentifier("movementDeleteVideos")
                }
                ToolbarItem(id: "finishVideoSelection", placement: .topBarTrailing) {
                    Button(L10n("Done")) { isSelecting = false; selection.removeAll() }
                        .disabled(isDeleting)
                        .accessibilityIdentifier("movementFinishSelection")
                }
            } else if !videos.isEmpty {
                ToolbarItem(id: "beginVideoSelection", placement: .topBarTrailing) {
                    Button(L10n("Select")) { isSelecting = true }
                        .accessibilityIdentifier("movementSelectVideos")
                }
            }
        }
        .disabled(isDeleting)
        .alert(L10n("Permanently delete selected videos?"), isPresented: $confirmingDeletion) {
            Button(L10n("Delete videos"), role: .destructive) { deleteSelected() }
            Button(L10n("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n("These saved copies will be permanently deleted from this phone. This cannot be undone."))
        }
        .onChange(of: videos.map(\.id)) { selection.formIntersection(Set(videos.map(\.id))) }
        #if DEBUG && targetEnvironment(simulator)
        .task {
            guard ProcessInfo.processInfo.arguments.contains("--ui-test-video-library"), store.sessions.isEmpty else { return }
            for index in 0..<4 {
                do {
                    let movie = try await makeMovementVideoTestFixture()
                    let trial = Trial(taskType: .fingerTap, side: index.isMultiple(of: 2) ? .right : .left,
                        source: .camera, stopCondition: .thirtySec,
                        startedAt: Date().addingTimeInterval(Double(-index) * 3600), samples: [], metrics: .empty)
                    let session = MovementSession(patientId: "UI-FIXTURE", trials: [])
                    let _: MovementSession = try await withCheckedThrowingContinuation { continuation in
                        store.saveAcceptedTrial(trial, in: session, temporaryVideoURL: movie) {
                            continuation.resume(with: $0)
                        }
                    }
                } catch { errorMessage = error.localizedDescription }
            }
        }
        #endif
    }

    private func exportButton(_ title: String, systemImage: String,
                              _ action: @escaping () throws -> URL) -> some View {
        Button {
            do {
                lastExport = try action()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private var videoSection: some View {
        Section {
                ForEach(videos) { trial in
                    if isSelecting {
                        Button {
                            if !selection.insert(trial.id).inserted { selection.remove(trial.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selection.contains(trial.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title2).frame(width: 44, height: 44)
                                videoLabel(trial)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(trial.taskType.displayName), \(trial.side.displayName)")
                        .accessibilityValue(selection.contains(trial.id) ? L10n("Selected") : L10n("Not selected"))
                        .accessibilityIdentifier("movementSelectVideo_\(trial.id)")
                    } else {
                        NavigationLink {
                            MovementVideoPlayerView(trial: trial, videoStore: store.videoStore)
                        } label: {
                            videoLabel(trial)
                        }
                        .accessibilityIdentifier("movementOpenVideo_\(trial.id)")
                        .contextMenu {
                            Button {
                                selection = [trial.id]
                                isSelecting = true
                            } label: {
                                Label(L10n("Select videos"), systemImage: "checkmark.circle")
                            }
                        }
                    }
                }
                if videos.isEmpty {
                    Label(L10n("No saved videos yet"), systemImage: "video.slash")
                        .accessibilityIdentifier("movementNoSavedVideos")
                }
                if let message { Text(message).fixedSize(horizontal: false, vertical: true) }
            } header: {
                Text(L10n("Recorded videos"))
            } footer: {
                Text(L10n("Deleting videos keeps your movement measurements. Copies you already shared are not deleted."))
            }
    }

    private func videoLabel(_ trial: Trial) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(trial.taskType.displayName) · \(trial.side.displayName)")
            Text(trial.startedAt, format: .dateTime.day().month().year().hour().minute())
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deleteSelected() {
        isDeleting = true
        message = nil
        store.deleteVideos(ids: selection) { result in
            isDeleting = false
            switch result {
            case .success(let outcome):
                selection.formIntersection(Set(videos.map(\.id)))
                message = outcome.failedCount == 0
                    ? String(format: L10n("Videos deleted: %d. Measurements kept."), outcome.deletedCount)
                    : L10n("Some videos could not be deleted. Please try again.")
            case .failure:
                message = L10n("Deletion could not be completed. Please try again to finish removing the video references.")
            }
        }
    }
}

/// Playback stays private. Sharing requires an explicit action on a playable saved file.
struct MovementVideoPlayerView: View {
    let trial: Trial
    var videoStore: MovementVideoStore = .shared
    @ObservedObject private var store = TaskSessionStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var playableURL: URL?
    @State private var confirmingDeletion = false
    @State private var isDeleting = false
    @State private var deletionError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let player {
                VideoPlayer(player: player)
                    .accessibilityIdentifier("movementVideoPlayer")
            } else {
                ContentUnavailableView(L10n("Video unavailable"), systemImage: "video.slash",
                    description: Text(L10n("This video is no longer available on this phone.")))
                    .accessibilityIdentifier("movementVideoUnavailable")
            }
        }
        .navigationTitle(L10n("View recording"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let url = playableURL {
                    ShareLink(item: url, preview: SharePreview(Text("\(trial.taskType.displayName) · \(trial.side.displayName)"))) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(L10n("Share video"))
                    .accessibilityIdentifier("movementShareVideo")
                    .disabled(isDeleting)
                }
                if store.sessions.contains(where: { $0.trials.contains { $0.id == trial.id && $0.video != nil } }) {
                    Button(role: .destructive) { confirmingDeletion = true } label: {
                        if isDeleting { ProgressView() }
                        else { Image(systemName: "trash") }
                    }
                    .disabled(isDeleting)
                    .accessibilityLabel(L10n("Delete video"))
                    .accessibilityIdentifier("movementDeleteVideo")
                }
            }
        }
        .alert(L10n("Permanently delete this video?"), isPresented: $confirmingDeletion) {
            Button(L10n("Delete video"), role: .destructive) {
                player?.pause()
                isDeleting = true
                store.deleteVideos(ids: [trial.id]) { result in
                    isDeleting = false
                    switch result {
                    case .success(let outcome) where outcome.failedCount == 0:
                        player = nil; playableURL = nil
                        dismiss()
                    default:
                        deletionError = L10n("Some videos could not be deleted. Please try again.")
                    }
                }
            }
            Button(L10n("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n("This saved copy will be permanently deleted from this phone. This cannot be undone."))
        }
        .alert(L10n("Video deletion failed"), isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
            Button(L10n("OK")) { deletionError = nil }
        } message: { Text(deletionError ?? "") }
        .safeAreaInset(edge: .bottom) {
            if playableURL != nil {
                VStack(spacing: 6) {
                    Text(L10n("Shared copies leave this app. Share only with your study team."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color(.systemBackground))
            }
        }
        .task {
            isLoading = true
            playableURL = nil
            do {
                let url = try videoStore.url(for: trial)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw MovementVideoStore.VideoError.unavailable
                }
                let asset = AVURLAsset(url: url)
                guard try await asset.load(.isPlayable),
                      !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
                    throw MovementVideoStore.VideoError.unavailable
                }
                guard !Task.isCancelled else { return }
                playableURL = url
                player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            } catch { player = nil; playableURL = nil }
            isLoading = false
        }
        .onDisappear { player?.pause(); player = nil; playableURL = nil }
    }
}

#Preview {
    NavigationStack { MovementExportView() }
}

#if DEBUG && targetEnvironment(simulator)
/// A silent, generated movie for simulator storage/playback tests, never a patient recording.
func makeMovementVideoTestFixture() async throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("mov")
    do {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                         kCVPixelBufferWidthKey as String: 64,
                                         kCVPixelBufferHeightKey as String: 64])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? MovementVideoStore.VideoError.unavailable }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<3 {
            var buffer: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
                                      nil, &buffer) == kCVReturnSuccess, let buffer else {
                throw MovementVideoStore.VideoError.unavailable
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, 220, CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            for _ in 0..<100 where !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
            }
            guard adapter.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)) else {
                throw writer.error ?? MovementVideoStore.VideoError.unavailable
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? MovementVideoStore.VideoError.unavailable }
        return url
    } catch {
        try? FileManager.default.removeItem(at: url)
        throw error
    }
}
#endif
