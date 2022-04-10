import UIKit
import AVFoundation
import CoreLocation
import Photos
import os

class ViewController: UIViewController {

    @IBOutlet weak var previewView: PreviewView!

    var spinner: UIActivityIndicatorView!

    let locationManager = CLLocationManager()

    let cameraManager = CameraManager()

    let permissionsManager = PermissionsManager()

    override func viewDidLoad() {
        super.viewDidLoad()
        os_log("in: view did load")

        previewView.session = cameraManager.session

        // last request stays on
        permissionsManager.askForCameraPermissions(cameraManager: cameraManager)
        permissionsManager.askForMicrophonePermissions()
        permissionsManager.askForSaveToPhotosPermissions()
        permissionsManager.askForLocationPermissions(locationManager: locationManager)

        cameraManager.launchConfigureSession(previewView: previewView)
        DispatchQueue.main.async {
            self.spinner = UIActivityIndicatorView(style: .large)
            self.spinner.color = UIColor.cyan
            self.previewView.addSubview(self.spinner)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        cameraManager.sessionQueue.async {
            switch self.cameraManager.setupResult {
            case .success:
                self.cameraManager.addObservers()
                self.cameraManager.session.startRunning()
                self.cameraManager.isSessionRunning = self.cameraManager.session.isRunning

            case .notAuthorized:
                DispatchQueue.main.async {
                    let changePrivacySetting = "Permission to use the camera is denied, please review settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when no camera access")
                    let alertController = UIAlertController(title: Bundle.main.appName, message: message, preferredStyle: .alert)

                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))

                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in
                                                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                                                          options: [:],
                                                                                          completionHandler: nil)
                    }))

                    self.present(alertController, animated: true, completion: nil)
                }

            case .configurationFailed:
                DispatchQueue.main.async {
                    let alertMsg = "Alert message when something goes wrong during capture session configuration"
                    let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                    let alertController = UIAlertController(title: Bundle.main.appName, message: message, preferredStyle: .alert)

                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))

                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        cameraManager.sessionQueue.async {
            if self.cameraManager.setupResult == .success {
                self.cameraManager.session.stopRunning()
                self.cameraManager.isSessionRunning = self.cameraManager.session.isRunning
                self.cameraManager.removeObservers()
            }
        }

        super.viewWillDisappear(animated)
    }


}
