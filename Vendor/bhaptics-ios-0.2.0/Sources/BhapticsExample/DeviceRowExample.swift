import SwiftUI
import BhapticsPlugin

public struct DeviceRowExample: View {
    @State var device: BhapticsDevice
    public init(device: BhapticsDevice) {
        self.device = device
    }
    public var body: some View {
        HStack {
            Text(device.deviceType).frame(minWidth: 100)
            Text(device.position.rawValue).frame(minWidth: 100)
            Text(device.connected ? "O" : "X")

            if (device.paired) {
                Button("Unpair") {
                    BhapticsViewModelExample.shared.unpair(device: device)
                }
            } else {
                Button("Pair") {
                    BhapticsViewModelExample.shared.pair(device: device)
                }
            }
        }
    }
}


struct DeviceRowExample_Previews: PreviewProvider {
    static var previews: some View {
        DeviceRowExample(device: BhapticsDevice(name: "Name", uuid: "uuid", peripheral: nil))
    }
}
