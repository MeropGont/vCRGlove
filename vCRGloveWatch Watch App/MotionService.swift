//
//  MotionService.swift
//  vCRGloveWatch Watch App
//
//  Created by Tactile Glove on 03.09.25.
//

import Foundation
import CoreMotion
import Combine
import WatchConnectivity

final class MotionService: ObservableObject {
    static let shared = MotionService()

    @Published var isRecording = false
    @Published var samplesPerSec: Double = 50
    @Published var rmsLast1s: Double = 0

    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private var fileHandle: FileHandle?
    private var oneSecBuffer = [Double]()
    private var lastWriteTime = CFAbsoluteTimeGetCurrent()

    private func csvURL() throws -> URL {
        let fmt = ISO8601DateFormatter()
        let name = "tremor_" + fmt.string(from: Date()).replacingOccurrences(of: ":", with: "-") + ".csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: "timestamp,ax,ay,az\n".data(using: .utf8))
        return url
    }

    func start() {
        guard !isRecording else { return }
        isRecording = true
        oneSecBuffer.removeAll()

        do {
            let url = try csvURL()
            fileHandle = try FileHandle(forWritingTo: url)
            fileHandle?.seekToEndOfFile()
        } catch {
            print("CSV create error:", error); isRecording = false; return
        }

        motion.deviceMotionUpdateInterval = 1.0 / samplesPerSec
        guard motion.isDeviceMotionAvailable else { print("DeviceMotion not available"); stop(); return }

        motion.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: queue) { [weak self] dm, err in
            guard let self, let dm else { return }
            let ua = dm.userAcceleration  // gravity already removed
            let t  = dm.timestamp
            let ax = ua.x, ay = ua.y, az = ua.z
            let mag = sqrt(ax*ax + ay*ay + az*az)

            // 1-second RMS (simple)
            self.oneSecBuffer.append(mag)
            if self.oneSecBuffer.count >= Int(self.samplesPerSec) {
                let meanSq = self.oneSecBuffer.reduce(0){$0 + $1*$1} / Double(self.oneSecBuffer.count)
                let rms = sqrt(meanSq)
                self.oneSecBuffer.removeAll(keepingCapacity: true)
                DispatchQueue.main.async { self.rmsLast1s = rms }
            }

            // append CSV line (ISO8601-ish timestamp)
            if let h = self.fileHandle {
                let line = String(format: "%.6f,%.6f,%.6f,%.6f\n", t, ax, ay, az)
                if let data = line.data(using: .utf8) { try? h.write(contentsOf: data) }
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        motion.stopDeviceMotionUpdates()
        if let h = fileHandle {
            try? h.close()
            fileHandle = nil
        }
    }

    func exportRecordingToPhone() {
        guard let url = FileManager.default.temporaryDirectory
            .contents?.sorted(by: { $0.path > $1.path }).first else { return } // last file heuristic
        WatchConnectivityManager.shared.transferFile(url, meta: ["type":"tremor", "sr":"\(Int(samplesPerSec))"])
    }
}

private extension URL {
    var contents: [URL]? { try? FileManager.default.contentsOfDirectory(at: self, includingPropertiesForKeys: nil) }
}
