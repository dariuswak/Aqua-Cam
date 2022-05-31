import AVFoundation
import Photos
import CoreLocation
import CoreBluetooth
import CoreMotion
import os

class PermissionsManager {

    func askForCameraPermissions(_ cameraManager: CameraManager) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break

        case .notDetermined:
            os_log("Asking for camera permissions")
            cameraManager.sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    os_log("Camera permissions denied")
                    cameraManager.setupResult = .notAuthorizedCamera
                }
                cameraManager.sessionQueue.resume()
            })

        default:
            os_log("Camera permissions has been denied")
            cameraManager.setupResult = .notAuthorizedCamera
        }
    }

    func askForMicrophonePermissions() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            os_log("Asking for microphone permissions")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if !granted {
                    os_log("Microphone permissions denied")
                }
            }
        }
    }

    func askForSaveToPhotosPermissions(_ cameraManager: CameraManager) {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            break

        case .notDetermined:
            os_log("Asking for photos permissions")
            cameraManager.sessionQueue.suspend()
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { outcome in
                if ![.authorized, .limited].contains(outcome) {
                    os_log("Photos permissions denied")
                    cameraManager.setupResult = .notAuthorizedAlbum
                }
                cameraManager.sessionQueue.resume()
            }

        default:
            os_log("Photos permissions has been denied")
            cameraManager.setupResult = .notAuthorizedAlbum
        }
    }

    func askForLocationPermissions(_ locationManager: CLLocationManager) {
        if locationManager.authorizationStatus == .notDetermined {
            os_log("Asking for location permissions")
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func askForBluetoothPermissions(_ bleCentralManager: BleCentralManager) {
        bleCentralManager.initiate()
    }

    func askForSensorPermissions(_ sensorManager: SensorManager) {
        switch CMAltimeter.authorizationStatus() {
        case .notDetermined:
            os_log("Asking for altimeter permissions")
            fallthrough
        case .authorized:
            sensorManager.initiate()
        default:
            os_log("Altimeter permissions has been denied")
            return
        }
    }

}
