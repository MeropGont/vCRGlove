import AVFoundation
import CoreImage
import Vision

/// Post-processes a new camera movie, never the live measurement signal.
enum MovementFaceMasker {
    static let version = 7
    enum MaskingError: Error { case unavailable, invalidFrame, timedOut }
    typealias FaceDetector = @Sendable (CIImage) throws -> [CGRect]

    // One process owns this directory. Startup removes drafts abandoned by termination.
    private static let workspace: Result<URL, Error> = Result {
        var root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vcr-private-camera", isDirectory: true)
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        return root
    }

    static func prepareWorkspace() { _ = workspace }

    static func recordingURL() throws -> URL {
        try workspace.get().appendingPathComponent(UUID().uuidString + ".mov")
    }

    static func isProcessedFile(_ url: URL) -> Bool {
        guard let directory = try? workspace.get() else { return false }
        return url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL
            && url.lastPathComponent.hasSuffix(".masked.mov")
    }

    static func handCrop(for bounds: CGRect) -> CGRect? {
        guard [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite),
              bounds.width >= 0.04, bounds.height >= 0.04,
              CGRect(x: 0, y: 0, width: 1, height: 1).contains(bounds) else { return nil }
        let crop = bounds.insetBy(dx: -max(0.04, bounds.width * 0.20),
            dy: -max(0.04, bounds.height * 0.20))
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        // Do not silently fall back to an almost full-frame recording.
        guard crop.width * crop.height <= 0.70 else { return nil }
        return crop
    }

    static func pixelCrop(_ normalized: CGRect?, in extent: CGRect) throws -> CGRect {
        guard let normalized else { return extent }
        guard [normalized.minX, normalized.minY, normalized.width, normalized.height].allSatisfy(\.isFinite),
              normalized.width > 0, normalized.height > 0,
              CGRect(x: 0, y: 0, width: 1, height: 1).contains(normalized) else { throw MaskingError.invalidFrame }
        let minX = floor(normalized.minX * extent.width / 2) * 2
        let minY = floor(normalized.minY * extent.height / 2) * 2
        let maxX = min(extent.width, ceil(normalized.maxX * extent.width / 2) * 2)
        let maxY = min(extent.height, ceil(normalized.maxY * extent.height / 2) * 2)
        guard maxX - minX >= 2, maxY - minY >= 2 else { throw MaskingError.invalidFrame }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Vision boxes and CI pixels both use a bottom-left origin after orientation normalization.
    static func maskRectangles(_ faces: [CGRect], in extent: CGRect) throws -> [CGRect] {
        try faces.map { face in
            guard [face.minX, face.minY, face.width, face.height].allSatisfy(\.isFinite),
                  face.size.width > 0, face.size.height > 0 else { throw MaskingError.invalidFrame }
            let pixels = CGRect(x: face.minX * extent.width + extent.minX,
                y: face.minY * extent.height + extent.minY,
                width: face.width * extent.width, height: face.height * extent.height)
            // Retain a safety margin without the original 50% increase in total width/height.
            return pixels.insetBy(dx: -max(12, pixels.width * 0.12),
                                  dy: -max(12, pixels.height * 0.12)).integral.intersection(extent)
        }
    }

    static func unrotateHalfTurn(_ box: CGRect) -> CGRect {
        CGRect(x: 1 - box.maxX, y: 1 - box.maxY, width: box.width, height: box.height)
    }

    /// Coalesce overlapping/nearly touching coverage, with bounded extra area.
    /// Never remove an isolated guard to make the image look cleaner.
    static func consolidatedMasks(_ input: [CGRect]) -> [CGRect] {
        var boxes = input.filter { !$0.isNull && !$0.isEmpty }.sorted {
            $0.minX == $1.minX ? $0.minY < $1.minY : $0.minX < $1.minX
        }
        var merged = true
        while merged {
            merged = false
            outer: for first in boxes.indices {
                for second in boxes.indices where second > first {
                    let a = boxes[first], b = boxes[second]
                    let intersection = a.intersection(b)
                    guard a.insetBy(dx: -12, dy: -12).intersects(b.insetBy(dx: -12, dy: -12)) else { continue }
                    let envelope = a.union(b)
                    let overlapArea = intersection.isNull || intersection.isEmpty ? 0
                        : intersection.width * intersection.height
                    let unionArea = a.width * a.height + b.width * b.height
                        - overlapArea
                    guard envelope.width * envelope.height <= unionArea * 1.25 else { continue }
                    boxes[first] = envelope
                    boxes.remove(at: second)
                    merged = true
                    break outer
                }
            }
        }
        return boxes
    }

    static func styledMask(_ box: CGRect) throws -> CIImage {
        // Round outside the protective rectangle, never cut into covered pixels.
        let radius = min(14, max(8, min(box.width, box.height) * 0.04))
        guard let mask = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
            "inputExtent": CIVector(cgRect: box.insetBy(dx: -radius, dy: -radius)),
            "inputRadius": radius,
            "inputColor": CIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)
        ])?.outputImage else { throw MaskingError.unavailable }
        return mask
    }

    private struct OpeningCoverage {
        var detections: [Double: [CGRect]] = [:]
        var masks: [Double: [CGRect]] = [:]
        var detectionSeconds = 0.0
        var trackingSeconds = 0.0
    }

    // Only the short prefix is decoded twice; its full-resolution detections are reused below.
    private static func openingCoverage(asset: AVAsset, track: AVAssetTrack,
        transform: CGAffineTransform, context: CIContext, nativeDetector: FaceMaskDetector,
        detector: FaceDetector?, deadline: Date) throws -> OpeningCoverage {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw MaskingError.unavailable }
        reader.add(output)
        defer { reader.cancelReading() }
        guard reader.startReading() else { throw reader.error ?? MaskingError.unavailable }
        var coverage = OpeningCoverage()
        var previews: [(time: Double, image: CIImage)] = []
        var firstTime: Double?
        var previousTime: Double?
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard Date() < deadline else { throw MaskingError.timedOut }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            guard pts.isNumeric, pts.seconds.isFinite, pts >= .zero,
                  previousTime == nil || pts.seconds > previousTime!,
                  let pixels = CMSampleBufferGetImageBuffer(sample) else { throw MaskingError.invalidFrame }
            let time = pts.seconds
            if firstTime == nil { firstTime = time }
            guard time - firstTime! <= 8, previews.count < 480 else { break }
            previousTime = time
            let found = try autoreleasepool { () throws -> Bool in
                let rotated = CIImage(cvPixelBuffer: pixels).transformed(by: transform)
                let image = rotated.transformed(by: CGAffineTransform(
                    translationX: -rotated.extent.minX, y: -rotated.extent.minY))
                let start = ProcessInfo.processInfo.systemUptime
                let faces = try detector?(image) ?? nativeDetector.detect(in: image)
                coverage.detectionSeconds += ProcessInfo.processInfo.systemUptime - start
                _ = try maskRectangles(faces, in: image.extent)
                coverage.detections[time] = faces
                // Rasterize tiny independent previews rather than retaining decoder pixel buffers.
                let scale = min(1, 160 / max(image.extent.width, image.extent.height))
                let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                guard let raster = context.createCGImage(small, from: small.extent) else {
                    throw MaskingError.invalidFrame
                }
                previews.append((time, CIImage(cgImage: raster)))
                guard !faces.isEmpty else { return false }
                let trackingStart = ProcessInfo.processInfo.systemUptime
                let backwards = FaceMaskTracks()
                for preview in previews.reversed() {
                    let boxes = try backwards.update(detections: preview.time == time ? faces : [],
                        image: preview.image, time: time - preview.time, tracksMisses: detector == nil)
                    coverage.masks[preview.time] = boxes
                }
                coverage.trackingSeconds += ProcessInfo.processInfo.systemUptime - trackingStart
                return true
            }
            if found { break }
        }
        if reader.status == .failed { throw reader.error ?? MaskingError.unavailable }
        return coverage
    }

    /// Consumes the raw draft on success, failure or cancellation. No unmasked fallback.
    static func consume(_ source: URL, handCrop: CGRect? = nil, detector: FaceDetector? = nil) async throws -> URL {
        defer { try? FileManager.default.removeItem(at: source) }
        let output = try workspace.get().appendingPathComponent(UUID().uuidString + ".masked.mov")
        var completed = false
        defer {
            if !completed { try? FileManager.default.removeItem(at: output) }
        }
        try Task.checkCancellation()
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw MaskingError.unavailable
        }
        let transform = try await track.load(.preferredTransform)
        let naturalSize = try await track.load(.naturalSize)
        let transformed = CGRect(origin: .zero, size: naturalSize).applying(transform)
        guard transformed.width.isFinite, transformed.height.isFinite,
              transformed.width >= 2, transformed.height >= 2,
              transformed.width <= 4096, transformed.height <= 4096 else { throw MaskingError.invalidFrame }
        let sourceExtent = CGRect(x: 0, y: 0, width: Int(ceil(transformed.width / 2)) * 2,
            height: Int(ceil(transformed.height / 2)) * 2)
        let crop = try pixelCrop(handCrop, in: sourceExtent)
        let width = Int(crop.width)
        let height = Int(crop.height)
        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        let reader = try AVAssetReader(asset: asset)
        let frames = AVAssetReaderTrackOutput(track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        frames.alwaysCopiesSampleData = false
        guard reader.canAdd(frames) else { throw MaskingError.unavailable }
        reader.add(frames)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        guard writer.canAdd(input) else { throw MaskingError.unavailable }
        writer.add(input)
        defer {
            reader.cancelReading()
            if !completed { writer.cancelWriting() }
        }
        guard writer.startWriting() else { throw writer.error ?? MaskingError.unavailable }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else { throw reader.error ?? MaskingError.unavailable }
        let context = CIContext(options: [.cacheIntermediates: false])
        let black = CIImage(color: .black)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let faceTracks = FaceMaskTracks()
        let nativeDetector = FaceMaskDetector(context: context)
        var previousPTS: CMTime?
        var endTime = CMTime.zero
        var count = 0
        var reusedFrames = 0
        var detectionSeconds = 0.0
        var trackingSeconds = 0.0
        let processingStart = ProcessInfo.processInfo.systemUptime
        let deadline = Date().addingTimeInterval(180)
        let opening = try openingCoverage(asset: asset, track: track, transform: transform,
            context: context, nativeDetector: nativeDetector, detector: detector, deadline: deadline)
        detectionSeconds += opening.detectionSeconds
        trackingSeconds += opening.trackingSeconds
        while let sample = frames.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard Date() < deadline else { throw MaskingError.timedOut }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            guard pts.isNumeric, pts.seconds.isFinite, pts >= .zero,
                  previousPTS == nil || pts > previousPTS!,
                  let pixels = CMSampleBufferGetImageBuffer(sample) else { throw MaskingError.invalidFrame }
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                guard writer.status == .writing, Date() < deadline else { throw MaskingError.unavailable }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            try autoreleasepool {
                let rotated = CIImage(cvPixelBuffer: pixels).transformed(by: transform)
                let image = rotated.transformed(by: CGAffineTransform(
                    translationX: -rotated.extent.minX, y: -rotated.extent.minY))
                let detectionStart = ProcessInfo.processInfo.systemUptime
                let detections = try opening.detections[pts.seconds]
                    ?? (detector?(image) ?? nativeDetector.detect(in: image))
                detectionSeconds += ProcessInfo.processInfo.systemUptime - detectionStart
                let trackingStart = ProcessInfo.processInfo.systemUptime
                let faces = try faceTracks.update(detections: detections, image: image,
                    time: pts.seconds, tracksMisses: detector == nil)
                trackingSeconds += ProcessInfo.processInfo.systemUptime - trackingStart
                let openingFaces = opening.masks[pts.seconds] ?? []
                let visibleMasks = try maskRectangles(faces.isEmpty ? openingFaces : faces, in: sourceExtent)
                    .filter { !$0.intersection(crop).isNull && !$0.intersection(crop).isEmpty }
                let boxes = consolidatedMasks(visibleMasks)
                // This frame was fully checked. Reuse its pixels only if no mask or orientation change is needed.
                if boxes.isEmpty, transform.isIdentity, crop == sourceExtent,
                   CVPixelBufferGetWidth(pixels) == width, CVPixelBufferGetHeight(pixels) == height {
                    guard adaptor.append(pixels, withPresentationTime: pts) else {
                        throw writer.error ?? MaskingError.unavailable
                    }
                    reusedFrames += 1
                    return
                }
                var masked = image.composited(over: black.cropped(to: sourceExtent))
                for box in boxes where !box.isNull && !box.isEmpty {
                    masked = try styledMask(box).composited(over: masked)
                }
                masked = masked.cropped(to: crop).transformed(by: CGAffineTransform(
                    translationX: -crop.minX, y: -crop.minY))
                guard let pool = adaptor.pixelBufferPool else { throw MaskingError.unavailable }
                var result: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &result) == kCVReturnSuccess,
                      let result else { throw MaskingError.unavailable }
                context.render(masked, to: result, bounds: extent, colorSpace: colorSpace)
                guard adaptor.append(result, withPresentationTime: pts) else {
                    throw writer.error ?? MaskingError.unavailable
                }
            }
            let duration = CMSampleBufferGetDuration(sample)
            let fallback = previousPTS.map { pts - $0 } ?? CMTime(value: 1, timescale: 30)
            endTime = pts + (duration.isNumeric && duration > .zero ? duration : fallback)
            previousPTS = pts
            count += 1
        }
        guard reader.status == .completed, count > 0 else { throw reader.error ?? MaskingError.unavailable }
        input.markAsFinished()
        writer.endSession(atSourceTime: endTime)
        await writer.finishWriting()
        try Task.checkCancellation()
        guard writer.status == .completed else { throw writer.error ?? MaskingError.unavailable }
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: output.path)
        // Do not publish the processed copy if the raw draft could not be removed.
        try FileManager.default.removeItem(at: source)
        completed = true
        print(String(format: "[VIDEO] Masking v%d: %d frames, %.2f s total, %.2f s detection, %.2f s tracking, %d direct frames",
            Int32(version), Int32(count), ProcessInfo.processInfo.systemUptime - processingStart,
            detectionSeconds, trackingSeconds, Int32(reusedFrames)))
        return output
    }
}

/// Each movie owns these reusable requests and shares its rendering context with Vision.
final class FaceMaskDetector {
    private let requests = [VNDetectFaceRectanglesRequest(), VNDetectFaceRectanglesRequest()]
    private let context: CIContext

    init(context: CIContext) { self.context = context }

    func detect(in image: CIImage) throws -> [CGRect] {
        var faces: [CGRect] = []
        for (index, request) in requests.enumerated() {
            let inverted = index == 1
            let input = inverted ? image.oriented(.down) : image
            try VNImageRequestHandler(ciImage: input, orientation: .up,
                options: [.ciContext: context]).perform([request])
            faces += (request.results ?? []).map {
                inverted ? MovementFaceMasker.unrotateHalfTurn($0.boundingBox) : $0.boundingBox
            }
        }
        return faces
    }
}

/// Spatial association only, not identity recognition. One current region per face, never a trail.
final class FaceMaskTracks {
    typealias AssociationPredictor = (CGRect, CIImage) throws -> CGRect?
    private let associationPredictor: AssociationPredictor?

    init(associationPredictor: AssociationPredictor? = nil) {
        self.associationPredictor = associationPredictor
    }

    private static func strongContinuation(from box: CGRect, to next: CGRect) -> Bool {
        guard next.width > 0, next.height > 0,
              [next.minX, next.minY, next.width, next.height].allSatisfy(\.isFinite) else { return false }
        let ratio = next.width * next.height / (box.width * box.height)
        return (0.5...2).contains(ratio)
            && hypot(next.midX - box.midX, next.midY - box.midY) <= max(box.width, box.height) * 0.75
    }

    private final class Track {
        var box: CGRect
        var lastSeen: Double
        var lastImage: CIImage
        var request: VNTrackObjectRequest?
        var sequence: VNSequenceRequestHandler?
        var attemptedSeed = false
        var edgeGuard: CGRect?
        var displayedBox: CGRect?
        var displayedAt: Double?

        init(box: CGRect, image: CIImage, time: Double) {
            self.box = box; lastImage = image; lastSeen = time
            edgeGuard = FaceMaskTracks.edgeCoverage(box)
        }

        @discardableResult
        func follow(_ image: CIImage, requiresStrongMatch: Bool = false) throws -> Bool {
            if request == nil {
                guard !attemptedSeed else { return false }
                attemptedSeed = true
                let request = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: box))
                request.trackingLevel = .accurate
                let sequence = VNSequenceRequestHandler()
                try sequence.perform([request], on: lastImage)
                guard let seed = request.results?.first as? VNDetectedObjectObservation,
                      seed.confidence >= 0.3 else { return false }
                request.inputObservation = seed
                self.request = request
                self.sequence = sequence
            }
            guard let request, let sequence else { return false }
            try sequence.perform([request], on: image)
            if let observation = request.results?.first as? VNDetectedObjectObservation,
               observation.confidence >= (requiresStrongMatch ? 0.7 : 0.3) {
                let next = observation.boundingBox
                guard next.width > 0, next.height > 0,
                      [next.minX, next.minY, next.width, next.height].allSatisfy(\.isFinite) else {
                    throw MovementFaceMasker.MaskingError.invalidFrame
                }
                if requiresStrongMatch {
                    guard FaceMaskTracks.strongContinuation(from: box, to: next) else { return false }
                }
                box = next
                request.inputObservation = observation
                return true
            }
            return false
        }

        func display(_ required: CGRect, time: Double) -> CGRect {
            defer { displayedAt = time }
            guard let old = displayedBox, let last = displayedAt else {
                displayedBox = required
                return required
            }
            let dt = max(0, time - last)
            if dt >= 0.4 {
                displayedBox = required
                return required
            }
            let alpha = 1 - exp(-dt / 0.10)
            let minX = min(required.minX, old.minX + (required.minX - old.minX) * alpha)
            let minY = min(required.minY, old.minY + (required.minY - old.minY) * alpha)
            let maxX = max(required.maxX, old.maxX + (required.maxX - old.maxX) * alpha)
            let maxY = max(required.maxY, old.maxY + (required.maxY - old.maxY) * alpha)
            let result = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            displayedBox = result
            return result
        }
    }

    private var tracks: [Track] = []

    private static func edgeCoverage(_ box: CGRect) -> CGRect? {
        let marginX = max(0.03, box.width * 0.12)
        let marginY = max(0.03, box.height * 0.12)
        let left = box.minX <= marginX
        let right = box.maxX >= 1 - marginX
        let bottom = box.minY <= marginY
        let top = box.maxY >= 1 - marginY
        guard left || right || bottom || top else { return nil }
        let minX = left ? 0 : box.minX
        let minY = bottom ? 0 : box.minY
        return CGRect(x: minX, y: minY, width: (right ? 1 : box.maxX) - minX,
            height: (top ? 1 : box.maxY) - minY)
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height / min(a.width * a.height, b.width * b.height)
    }

    private static func nearby(_ a: CGRect, _ b: CGRect) -> Bool {
        overlap(a, b) > 0.1 || hypot(a.midX - b.midX, a.midY - b.midY)
            < max(a.width, a.height, b.width, b.height) * 0.75
    }

    func update(detections: [CGRect], image: CIImage, time: Double, tracksMisses: Bool) throws -> [CGRect] {
        // Stop following unconfirmed objects after 2 s. A confirmed edge-face region
        // stays covered: partial faces can remain visible after detection/tracking fails.
        tracks.removeAll { time - $0.lastSeen > 2 && $0.edgeGuard == nil }
        var unique: [CGRect] = []
        for box in detections {
            guard box.size.width > 0, box.size.height > 0,
                  [box.minX, box.minY, box.width, box.height].allSatisfy(\.isFinite) else {
                throw MovementFaceMasker.MaskingError.invalidFrame
            }
            if let index = unique.firstIndex(where: { Self.overlap($0, box) > 0.6 }) {
                unique[index] = unique[index].union(box)
            } else { unique.append(box) }
        }
        var unmatched = Set(tracks.indices)
        var predicted = Set<Int>()
        if tracksMisses && !unique.isEmpty {
            for index in tracks.indices where time - tracks[index].lastSeen <= 0.5
                && !unique.contains(where: { Self.nearby(tracks[index].box, $0) }) {
                // Try a short, high-confidence continuation before inventing another face.
                if let associationPredictor {
                    if let next = try associationPredictor(tracks[index].box, image),
                       Self.strongContinuation(from: tracks[index].box, to: next) {
                        tracks[index].box = next
                        predicted.insert(index)
                    }
                } else if try tracks[index].follow(image, requiresStrongMatch: true) { predicted.insert(index) }
            }
        }
        for box in unique {
            // Nearest spatial match, bounded by face size so separate people stay separate.
            let candidate = unmatched.filter {
                let old = tracks[$0].box
                return Self.nearby(old, box)
            }.min { a, b in
                hypot(tracks[a].box.midX - box.midX, tracks[a].box.midY - box.midY)
                    < hypot(tracks[b].box.midX - box.midX, tracks[b].box.midY - box.midY)
            }
            if let index = candidate {
                let track = tracks[index]
                track.box = box; track.lastSeen = time; track.lastImage = image
                track.edgeGuard = Self.edgeCoverage(box)
                track.request = nil; track.sequence = nil
                track.attemptedSeed = false
                unmatched.remove(index)
            } else { tracks.append(Track(box: box, image: image, time: time)) }
        }
        if tracksMisses {
            for index in unmatched where time - tracks[index].lastSeen <= 2 && !predicted.contains(index) {
                try tracks[index].follow(image)
            }
        }
        return tracks.map { track in
            let required: CGRect
            if let edge = track.edgeGuard {
                required = time - track.lastSeen <= 2 ? edge.union(track.box) : edge
            } else { required = track.box }
            return track.display(required, time: time)
        }
    }
}
