import AVFoundation
import Photos
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
                    cameraManager.setupResult = .notAuthorizedCamera
                }
                cameraManager.sessionQueue.resume()
            })

        default:
            cameraManager.setupResult = .notAuthorizedCamera
        }
    }

    func askForMicrophonePermissions() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
    }

    func askForSaveToPhotosPermissions(cameraManager: CameraManager) {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized:
            break
        case .limited:
            break

        case .notDetermined:
            cameraManager.sessionQueue.suspend()
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { outcome in
                if ![.authorized, .limited].contains(outcome) {
                    cameraManager.setupResult = .notAuthorizedAlbum
                }
                cameraManager.sessionQueue.resume()
            }

        default:
            cameraManager.setupResult = .notAuthorizedAlbum
        }
    }

    func askForLocationPermissions(locationManager: CLLocationManager) {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

}
