//
//  ContentView.swift
//  vCRGloveWatch Watch App
//
//  Created by Tactile Glove on 30.08.25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var motion = MotionService.shared

    var body: some View {
        VStack(spacing: 10) {
            Text(motion.isRecording ? "Recording…" : "Idle")
                .font(.headline)

            Text(String(format: "RMS(1s): %.4f g", motion.rmsLast1s))
                .monospacedDigit()

            HStack {
                Button("Ping iPhone") {
                    WatchConnectivityManager.shared.sendPing()
                }
                .onAppear { _ = WatchConnectivityManager.shared } // ensure activation

                Button(motion.isRecording ? "Stop" : "Start") {
                    motion.isRecording ? motion.stop() : motion.start()
                }
                Button("Send") {
                    motion.exportRecordingToPhone()
                }.disabled(motion.isRecording)
            }
        }
        .onAppear { _ = WatchConnectivityManager.shared } // ensure WCSession activates
        .padding()
    }
}
