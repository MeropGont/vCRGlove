## 

### import
```
import BhapticsPlugin

var kit: BhapticsKit! = BhapticsKit()
 
```

### Scan/StopScn
```
let scanning = kit.isScanning()
if (scanning) {
  kit.stopScan()
} else {
  kit.scan()
}
```

### GetDevices and Pair/Unpair
```
let deviceList = kit.getDevices()

kit.pair(device: device)
kit.unpair(device: device)

```

### PlayMotors/TurnOff
```
let position = BhapticsPosition.Vest
let motors = [Int](repeating: intensity, count: 40)
let millis = 1000 // for 1 second

kit.playMotors(position: position, arr: motors, durationMillis: millis)

kit.turnOffMotors()
```

## Example 
* Sample app is under SampleApp folder. Please check out the whole example.
![img_2.png](img_2.png)