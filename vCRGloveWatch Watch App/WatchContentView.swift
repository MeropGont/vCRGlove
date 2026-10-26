//
//  ContentView.swift
//  vCRGloveWatch Watch App
//
//  Created by Tactile Glove on 30.08.25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var motion = MotionService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 10) {
            Text(motion.isStreaming ? "Streaming to iPhone…"
                 : motion.isRecording ? "Recording…" : "Idle")
                .font(.headline)

            Text(String(format: "RMS(1s): %.4f g", motion.rmsLast1s))
                .monospacedDigit()

            HStack {
                Button(motion.isStreaming ? "Stop Stream" : "Stream") {
                    if motion.isStreaming { motion.stopStreaming() }
                    else { motion.startStreaming() }
                }
                .disabled(motion.isPhoneControlled)

                Button(motion.isRecording ? "Stop Rec" : "Record") {
                    motion.isRecording ? motion.stop() : motion.start()
                }
                .disabled(motion.isStreaming || motion.isPhoneControlled)
            }

            if motion.isPhoneControlled {
                Text("Controlled by iPhone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Ping iPhone") {
                    WatchConnectivityManager.shared.sendPing()
                }

                Button("Send") {
                    motion.exportRecordingToPhone()
                }
                .disabled(motion.isRecording)
            }
        }
        .onAppear { _ = WatchConnectivityManager.shared } // ensure WCSession activates
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { motion.stopStreaming() }
        }
        .padding()
    }
}
