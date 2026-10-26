//
//  MovementExportView.swift
//  vCRGlove
//
//  Data overview, private videos, read-only file previews and explicit sharing.
//  Generated JSON/CSV files remain in Documents/vcr/tasks/exports/.
//

import SwiftUI
import AVKit
import UIKit

struct MovementExportView: View {
    private let showsVideoLibrary: Bool
    @ObservedObject private var store = TaskSessionStore.shared
    @StateObject private var exportController = StudyDataExportController()
    @AppStorage(MovementVideoPreference.key) private var saveTaskVideos = true

    @State private var openDocument: MovementDataDocument?
    @State private var errorMessage: String?
    @State private var selection = Set<UUID>()
    @State private var isSelecting = false
    @State private var confirmingDeletion = false
    @State private var isDeleting = false
    @State private var message: String?

    init(showsVideoLibrary: Bool = false) {
        self.showsVideoLibrary = showsVideoLibrary
    }

    private var trialCount: Int { store.sessions.reduce(0) { $0 + $1.trials.count } }
    private var videos: [Trial] {
        var seen = Set<UUID>()
        return store.sessions.flatMap(\.trials).filter { $0.video != nil && seen.insert($0.id).inserted }
            .sorted { $0.startedAt > $1.startedAt }
    }
    private var selectedURLs: [URL] {
        (try? store.videoStore.shareURLs(for: videos.filter { selection.contains($0.id) })) ?? []
    }
    private var preparingVideos: [Trial] {
        store.sessions.flatMap(\.trials).filter {
            $0.video == nil && store.videoPreparationStates[$0.id] != nil
        }.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        Form {
            if showsVideoLibrary {
                videoSection
            } else {
                Section {
                    LabeledContent(L10n("Sessions"), value: "\(store.sessions.count)")
                        .accessibilityIdentifier("movementRecordedSessionCount")
                    LabeledContent(L10n("Trials"), value: "\(trialCount)")
                    Toggle(L10n("Save task videos"), isOn: $saveTaskVideos)
                        .accessibilityIdentifier("movementSaveTaskVideos")
                } header: {
                    Text(L10n("Recorded data"))
                } footer: {
                    Text(L10n("Applies to new recordings. Measurements are always saved. Existing videos are kept."))
                }

                Section {
                    NavigationLink {
                        MovementExportView(showsVideoLibrary: true)
                    } label: {
                        HStack {
                            Label(L10n("Recorded videos"), systemImage: "folder")
                            Spacer()
                            if preparingVideos.contains(where: { store.videoPreparationStates[$0.id] != .unavailable }) {
                                ProgressView().accessibilityLabel(L10n("Preparing video…"))
                            }
                            Text(videos.count, format: .number).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("movementVideoLibrary")
                    .accessibilityValue("\(videos.count)")
                    documentButton(L10n("JSON (full sessions)"), systemImage: "doc.badge.gearshape") {
                        try TaskSessionExporter.exportJSON(store.sessions)
                    }
                    .accessibilityIdentifier("movementOpenJSON")
                    documentButton(L10n("CSV — metrics per trial"), systemImage: "tablecells") {
                        try TaskSessionExporter.exportMetricsCSV(store.sessions)
                    }
                    .accessibilityIdentifier("movementOpenMetrics")
                    documentButton(L10n("CSV — raw samples"), systemImage: "waveform.path") {
                        try TaskSessionExporter.exportSamplesCSV(store.sessions)
                    }
                    .accessibilityIdentifier("movementOpenSamples")
                    if store.sessions.contains(where: { $0.trials.contains(where: { $0.fingerTappingAngle != nil }) }) {
                        documentButton(L10n("CSV — finger-tapping angles"), systemImage: "angle") {
                            try TaskSessionExporter.exportFingerTappingAnglesCSV(store.sessions)
                        }
                        .accessibilityIdentifier("movementExportAngles")
                    }
                } header: {
                    Text(L10n("Data files"))
                }

                StudyDataExportSection(controller: exportController)

                if let errorMessage {
                    Section {
                        Text(L10n(errorMessage))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .modifier(StudyDataExportPresentation(controller: exportController))
        .sheet(item: $openDocument) { document in
            MovementDataDocumentView(document: document)
        }
        .navigationTitle(L10n(showsVideoLibrary ? "Recorded videos" : "Data"))
        .toolbar {
            if showsVideoLibrary && isSelecting {
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
            } else if showsVideoLibrary && !videos.isEmpty {
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
                        startedAt: Date().addingTimeInterval(Double(-index) * 3600), samples: [], metrics: .empty,
                        fingerTappingAngle: .init(samples: [.init(t: 0, degrees: 0), .init(t: 0.1, degrees: nil)]))
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

    private func documentButton(_ title: String, systemImage: String,
                              _ action: @escaping () throws -> URL) -> some View {
        Button {
            do {
                openDocument = MovementDataDocument(url: try action(), title: title)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        } label: {
            Label(title, systemImage: systemImage)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(store.sessions.isEmpty || exportController.preparing)
    }

    private var videoSection: some View {
        Section {
                ForEach(preparingVideos) { trial in
                    VStack(alignment: .leading, spacing: 6) {
                        videoLabel(trial)
                        if store.videoPreparationStates[trial.id] == .unavailable {
                            Label(L10n("Video not saved. Your measurement is saved."), systemImage: "video.slash")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            HStack {
                                ProgressView()
                                Text(L10n("Preparing video…")).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("movementPreparingVideo_\(trial.id)")
                }
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
                if videos.isEmpty && preparingVideos.isEmpty {
                    Label(L10n("No saved videos yet"), systemImage: "video.slash")
                        .accessibilityIdentifier("movementNoSavedVideos")
                }
                if let message { Text(message).fixedSize(horizontal: false, vertical: true) }
            } header: {
                Text(L10n("Recorded videos"))
            } footer: {
                if preparingVideos.contains(where: { store.videoPreparationStates[$0.id] != .unavailable }) {
                    Text(L10n("You can continue your tasks. Keep the app open until videos are ready."))
                }
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

struct MovementDataDocument: Identifiable {
    let url: URL
    let title: String
    var id: URL { url }
}

private struct MovementDataDocumentView: View {
    let document: MovementDataDocument
    @Environment(\.dismiss) private var dismiss
    @State private var contents: String?
    @State private var readFailed = false
    @State private var choosingApp = false

    var body: some View {
        NavigationStack {
            Group {
                if let contents {
                    MovementDocumentPreview(contents: contents)
                } else if readFailed {
                    ContentUnavailableView(L10n("File unavailable"), systemImage: "doc.badge.exclamationmark")
                } else { ProgressView() }
            }
                .navigationTitle(document.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n("Done")) { dismiss() }
                            .accessibilityIdentifier("movementFileDone")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { choosingApp = true } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(L10n("Open in…"))
                        .accessibilityIdentifier("movementFileOpenIn")
                    }
                }
        }
        .sheet(isPresented: $choosingApp) {
            FullDataShareSheet(url: document.url) { choosingApp = false }
        }
        .task(id: document.url) {
            do {
                let url = document.url
                let text = try await Task.detached(priority: .userInitiated) {
                    try String(contentsOf: url, encoding: .utf8)
                }.value
                if !Task.isCancelled { contents = text }
            } catch { if !Task.isCancelled { readFailed = true } }
        }
    }
}

private struct MovementDocumentPreview: UIViewRepresentable {
    let contents: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isSelectable = true
        view.adjustsFontForContentSizeCategory = true
        view.font = UIFontMetrics(forTextStyle: .body).scaledFont(for:
            .monospacedSystemFont(ofSize: 14, weight: .regular))
        view.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "movementDocumentText"
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != contents { view.text = contents }
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
func makeMovementVideoTestFixture(width: Int = 64, height: Int = 64,
                                  transform: CGAffineTransform = .identity,
                                  startPTS: CMTime = .zero,
                                  frameStep: CMTime = CMTime(value: 1, timescale: 10)) async throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("mov")
    do {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.transform = transform
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                         kCVPixelBufferWidthKey as String: width,
                                         kCVPixelBufferHeightKey as String: height])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? MovementVideoStore.VideoError.unavailable }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<3 {
            var buffer: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
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
            guard adapter.append(buffer, withPresentationTime: startPTS + CMTimeMultiply(frameStep, multiplier: Int32(frame))) else {
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
