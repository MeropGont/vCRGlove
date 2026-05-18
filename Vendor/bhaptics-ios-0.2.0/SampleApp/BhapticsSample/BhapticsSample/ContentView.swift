//
//  ContentView.swift
//  ttttttttttttttttt
//
//  Created by Choi Sangwon on 2022/12/29.
//

import SwiftUI
import BhapticsExample
import BhapticsPlugin

let PositionOptions = [BhapticsPosition.Vest, BhapticsPosition.ForearmL
]

struct ContentView: View {
    @StateObject private var viewModel = BhapticsViewModelExample.shared

    @State var position = PositionOptions[0]
    @State var intensityText = "100"
    @State var millisText = "1000"
    @State var intensity = 100
    @State var millis = 100

    func toggleScan() {
        viewModel.toggleScanning()
    }

    var body: some View {
        VStack {
            Button("\(viewModel.kit.isScanning() ? "Scanning" : "Scan")") {
                toggleScan()
            }
            HStack {
                Picker("Position", selection: $position) {
                    ForEach(PositionOptions, id: \.self) {
                        Text($0.name)
                    }
                }
                        .pickerStyle(.automatic)

                TextField("Input", text: $intensityText)
                        .frame(minWidth: 60)
                TextField("Millis", text: $millisText)
                        .frame(minWidth: 60)
                Button("Play") {
                    let intVal = Int(intensityText)
                    if (intVal == nil) {
                        intensity = 100
                    } else {
                        intensity = min(100, max(0, intVal!))
                    }
                    let intValMillis = Int(millisText)
                    if (intValMillis == nil) {
                        millis = 1000
                    } else {
                        millis = min(10000, max(40, intVal!))
                    }
                    intensityText = String(intensity)

//                    let motors = [Int](repeating: intensity, count: 20)
                    let motors = [Int](repeating: intensity, count: 40)

                    viewModel.kit.playMotors(position: position, arr: motors, duratioinMillis: millis)
                
                }
                        .border(Color.gray)

                Button("Turn Off") {
                    viewModel.kit.turnOffMotors()
                }
                        .border(.gray)

            }
            
            DeviceListExample()
        }
        .padding()
        .frame(minWidth: 400)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
