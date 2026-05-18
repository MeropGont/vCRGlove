//
// Created by Choi Sangwon on 2022/12/29.
//

import Foundation

//
// Created by Choi Sangwon on 2022/12/22.
//

import Foundation
import SwiftUI

public struct DeviceListExample: View {
    @ObservedObject var viewModel = BhapticsViewModelExample.shared

    let height: CGFloat = 400
    public init() {}

    public var body: some View {
        VStack {
            if (viewModel.deviceList.count == 0) {
                Text("No paired device")
            } else {
                List(viewModel.deviceList) { device in
                    DeviceRowExample(device: device)
                }

            }

        }.frame(height: height)
    }
}


public struct DeviceListExample_Previews: PreviewProvider {
    public static var previews: some View {
        DeviceListExample()
    }
}
