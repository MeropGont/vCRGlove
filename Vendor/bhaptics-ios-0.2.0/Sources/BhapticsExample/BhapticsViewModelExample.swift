//
// Created by Choi Sangwon on 2022/12/28.
//
import BhapticsPlugin
import Foundation

public class BhapticsViewModelExample: ObservableObject {
    public static let shared = BhapticsViewModelExample()

    public var kit: BhapticsKit!

    @Published var isScanning = false
    @Published var deviceList: [BhapticsDevice] = []

    public init() {
        kit = BhapticsKit(delegate: self)
        deviceList = kit.getDevices()
        isScanning = kit.isScanning()
    }

    public func pair(device: BhapticsDevice) {
        kit.pair(device: device)
    }

    public func unpair(device: BhapticsDevice) {
        kit.unpair(device: device)
    }
    public func pair(id: String) {
        let device = deviceList.first(where: {$0.uuid == id})
        if (device == nil) {
            print("pair returned nil \(id)")
            return
        }

        kit.pair(device: device!)
    }

    public func unpair(id: String) {
        let device = deviceList.first(where: {$0.uuid == id})
        if (device == nil) {
            print("unpair returned nil \(id)")
            return
        }

        kit.unpair(device: device!)
    }

    public func refreshDevices() {
        deviceList = kit.getDevices()
    }

    public func toggleScanning() -> Bool {
        isScanning = kit.toggleScanning()
        return isScanning
    }

    private func updateDevice(devices: [BhapticsDevice]) {
        deviceList = devices
    }
}

extension BhapticsViewModelExample: BhapticsKitDelegate {
    public func bHapticsKit(_ kit: BhapticsKit, bleStateChange state: Bool) {
        if (state) {
            kit.scan()
            isScanning = kit.isScanning()
        }
    }

    public func bHapticsKit(_ kit: BhapticsKit, deviceStateUpdated devices: [BhapticsDevice]) {
        updateDevice(devices: devices)
    }

    public func bHapticsKit(_ kit: BhapticsKit, didConnect device: BhapticsDevice) {
        updateDevice(devices: kit.getDevices())
    }

    public func bHapticsKit(_ kit: BhapticsKit, didDisconnect device: BhapticsDevice) {
        updateDevice(devices: kit.getDevices())
    }
}

