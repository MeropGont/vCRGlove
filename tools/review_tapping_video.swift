// Read-only video sampling for independent visual review; not an app analyzer.
import Foundation
import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

enum ReviewError: Error { case invalidArguments, invalidVideo, outputExists, decodeFailed }

func run() throws {
let args = CommandLine.arguments
guard args.count == 6,
      let start = Double(args[3]), let end = Double(args[4]), let fps = Double(args[5]),
      start.isFinite, end.isFinite, fps.isFinite,
      start >= 0, end > start, fps > 0, fps <= 30 else {
    fputs("Usage: review-tapping-video VIDEO NEW_OUTPUT_DIRECTORY START_SECONDS END_SECONDS FPS\n", stderr)
    throw ReviewError.invalidArguments
}
let source = URL(fileURLWithPath: args[1]).standardizedFileURL.resolvingSymlinksInPath()
let directory = URL(fileURLWithPath: args[2]).standardizedFileURL.resolvingSymlinksInPath()
let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
guard #filePath.hasPrefix("/") else {
    fputs("Compile this tool using the absolute path of its Swift source.\n", stderr)
    throw ReviewError.invalidArguments
}
guard !directory.path.hasPrefix(repo.path + "/"), directory != repo else {
    throw ReviewError.invalidArguments
}
let fm = FileManager.default
guard !fm.fileExists(atPath: directory.path) else { throw ReviewError.outputExists }
let sourceHash = SHA256.hash(data: try Data(contentsOf: source, options: .mappedIfSafe))
    .map { String(format: "%02x", $0) }.joined()
let asset = AVURLAsset(url: source)
guard let track = asset.tracks(withMediaType: .video).first,
      end <= asset.duration.seconds + 0.001 else { throw ReviewError.invalidVideo }
let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
])
guard reader.canAdd(output) else { throw ReviewError.invalidVideo }
reader.add(output)
guard reader.startReading() else { throw reader.error ?? ReviewError.decodeFailed }
try fm.createDirectory(at: directory, withIntermediateDirectories: false,
                       attributes: [.posixPermissions: 0o700])
let context = CIContext()
var frames: [[String: Any]] = []
var next = start
var previous = -Double.infinity
var firstPTS: Double?
var lastPTS: Double?
var decoded = 0
do {
    while let sample = output.copyNextSampleBuffer() {
        let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        guard t.isFinite, t > previous else { throw ReviewError.invalidVideo }
        previous = t
        if firstPTS == nil { firstPTS = t }
        lastPTS = t
        decoded += 1
        guard t >= start, t < end, t + 0.000001 >= next else { continue }
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { throw ReviewError.decodeFailed }
        let oriented = CIImage(cvPixelBuffer: buffer).transformed(by: track.preferredTransform)
        guard let image = context.createCGImage(oriented, from: oriented.extent) else {
            throw ReviewError.decodeFailed
        }
        let name = String(format: "frame-%04d.png", frames.count)
        let url = directory.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                UTType.png.identifier as CFString, 1, nil) else { throw ReviewError.decodeFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ReviewError.decodeFailed }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        frames.append(["file": name, "pts_seconds": t, "width": image.width, "height": image.height])
        next += 1 / fps
        // A decoding gap must not manufacture multiple copies of the next frame.
        if next <= t { next = t + 1 / fps }
    }
    guard reader.status == .completed, !frames.isEmpty else {
        throw reader.error ?? ReviewError.decodeFailed
    }
    let afterHash = SHA256.hash(data: try Data(contentsOf: source, options: .mappedIfSafe))
        .map { String(format: "%02x", $0) }.joined()
    guard afterHash == sourceHash else { throw ReviewError.invalidVideo }
    let manifest: [String: Any] = [
        "format_version": 1, "video_file": source.lastPathComponent,
        "video_sha256": sourceHash,
        "video_byte_count": try fm.attributesOfItem(atPath: source.path)[.size]!,
        "duration_seconds": asset.duration.seconds,
        "nominal_fps": track.nominalFrameRate,
        "decoded_frame_count": decoded, "first_pts_seconds": firstPTS!,
        "last_pts_seconds": lastPTS!, "requested_start_seconds": start,
        "requested_end_seconds": end, "requested_sampling_fps": fps,
        "signal_video_synchronization_verified": false, "frames": frames
    ]
    let manifestURL = directory.appendingPathComponent("frames.json")
    try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        .write(to: manifestURL, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
    print("Extracted \(frames.count) frames; decoded \(decoded). Manifest: \(manifestURL.path)")
} catch {
    // Only this invocation's new directory is removed on failure.
    try? fm.removeItem(at: directory)
    throw error
}
}

do { try run() }
catch {
    fputs("Video review failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
