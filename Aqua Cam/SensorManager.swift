import CoreMotion
import os

class SensorManager: NSObject {

    let altimeter = CMAltimeter()

    let queue = OperationQueue()

    @objc dynamic var pressure: Int = 0

    func initiate() {
        queue.name = "Altimeter Queue"
        altimeter.startRelativeAltitudeUpdates(to: queue, withHandler: handleRelativeAltitude)
    }

    func handleRelativeAltitude(data: CMAltitudeData?, error: Error?) {
        guard let data = data, error == nil else {
            os_log("Error from altimeter: \(String(describing: error))")
            return
        }
        let currentPressure = Int(truncating: data.relativeAltitude) / 10
        if self.pressure != currentPressure {
            self.pressure = currentPressure
            os_log("Seal pressure changed to: \(self.pressure)")
        }
    }

}
