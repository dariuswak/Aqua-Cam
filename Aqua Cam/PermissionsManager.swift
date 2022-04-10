import AVFoundation
import CoreLocation

class PermissionsManager {

    func askForCameraPermissions(cameraManager: CameraManager) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break

        case .notDetermined:
            cameraManager.sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    cameraManager.setupResult = .notAuthorized
                }
                cameraManager.sessionQueue.resume()
            })

        default:
            cameraManager.setupResult = .notAuthorized
        }
    }

    func askForMicrophonePermissions() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
    }

    func askForSaveToPhotosPermissions() {
        // TODO
    }

    func askForLocationPermissions(locationManager: CLLocationManager) {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

}
