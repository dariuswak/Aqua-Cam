import UIKit
import AVFoundation
import Photos
import os

class ViewController: UIViewController {

    @IBOutlet weak var previewView: PreviewView!

    @IBAction func openSettings() {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                  options: [:],
                                  completionHandler: nil)
    }

    // shutter button
    @IBAction func shutterPressed() {
        if !cameraManager.session.isRunning {
            os_log("Attempting to restart the session")
            cameraManager.sessionQueue.async {
                self.cameraManager.session.startRunning()
                if !self.cameraManager.session.isRunning {
                    os_log("Unable to resume session")
                }
            }
            return
        }
        if previewView.isHidden {
            os_log("Waking up from sleep")
            cameraManager.sessionQueue.async {
                self.cameraManager.videoDeviceInput.ports
                    .filter { port in port.mediaType == AVMediaType.video }
                    .forEach { port in
                        os_log("Enabling video port: \(port)")
                        port.isEnabled = true
                    }
                DispatchQueue.main.async {
                    self.previewView.isHidden = false
                    os_log("Wakeup from sleep finished")
                }
            }
            return
        }
        if (cameraManager.movieFileOutput != nil) {
            os_log("Toggling video recording")
            cameraManager.toggleMovieRecording()
        } else {
            os_log("Capturing photo")
            cameraManager.capturePhoto(previewView: previewView, viewController: self)
        }
    }

    // 1st button - focus
    // triple click - sleep (shutter to wake)
    @IBAction func focusButton() {
        multiClick.on(count: 3) {
            os_log("Entering sleep")
            self.previewView.isHidden = true
            cameraManager.sessionQueue.async {
                self.cameraManager.videoDeviceInput.ports
                    .filter { port in port.mediaType == AVMediaType.video }
                    .forEach { port in
                        os_log("Disabling video port: \(port)")
                        port.isEnabled = false
                    }
            }
        } else: {
            os_log("Locking focus and exposure (cycle)")
            cameraManager.cycleLockFocusAndExposureInCentre(viewController: self)
        }
    }

    // 2nd button - mode
    // click - change camera
    // double click - photo/video
    // click during video recording - take photo
    @IBAction func modePressed() {
        if cameraManager.movieFileOutput?.isRecording == true {
            os_log("Capturing photo during movie recording")
            cameraManager.capturePhoto(previewView: previewView, viewController: self)
        } else {
            multiClick.on(count: 2) {
                os_log("Changing mode: photo/video")
                cameraManager.sessionQueue.async {
                    self.cameraManager.cyclePhotoAndVideo()
                }
            } else: {
                os_log("Changing camera (cycle)")
                cameraManager.sessionQueue.async {
                    self.cameraManager.changeCamera()
                }
            }
        }
    }

    @IBOutlet weak var capturingLivePhotoIndicator: UIButton!

    @IBOutlet weak var processingIndicator: UIActivityIndicatorView!

    @IBOutlet weak var focusIndicator: UIImageView!

    @IBOutlet weak var recordingTime: UILabel!

    @IBOutlet weak var bluetoothIndicator: UIButton!

    let cameraManager = CameraManager()

    @objc let bleCentralManager = BleCentralManager()

    let permissionsManager = PermissionsManager()

    let multiClick = TimedMultiClick()

    var keyValueObservations = [NSKeyValueObservation]()

    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        previewView.session = cameraManager.session

        os_log("Checking permissions")
        permissionsManager.askForCameraPermissions(cameraManager)
        permissionsManager.askForMicrophonePermissions()
        permissionsManager.askForSaveToPhotosPermissions(cameraManager)
        permissionsManager.askForLocationPermissions(cameraManager.locationManager)
        permissionsManager.askForBluetoothPermissions(bleCentralManager)

        cameraManager.launchConfigureSession(previewView: previewView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        cameraManager.sessionQueue.async {
            switch self.cameraManager.setupResult {
            case .success:
                os_log("Starting the session")
                self.cameraManager.addObservers()
                self.cameraManager.session.startRunning()

            case .notAuthorizedCamera:
                os_log("Alert about camera permissions")
                DispatchQueue.main.async {
                    let changePrivacySetting = "Permission to use the camera is denied, please review settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when no camera access")
                    let alertController = UIAlertController(title: Bundle.main.appName, message: message, preferredStyle: .alert)

                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))

                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in self.openSettings() }))

                    self.present(alertController, animated: true, completion: nil)
                }

            case .notAuthorizedAlbum:
                os_log("Alert about photos permissions")
                DispatchQueue.main.async {
                    let changePrivacySetting = "Permission to save to album is denied, please review settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when no album access")
                    let alertController = UIAlertController(title: Bundle.main.appName, message: message, preferredStyle: .alert)

                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))

                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in self.openSettings() }))

                    self.present(alertController, animated: true, completion: nil)
                }

            case .configurationFailed:
                os_log("Alert about configuration failure")
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
        addObservers()
    }

    override func viewWillDisappear(_ animated: Bool) {
        cameraManager.sessionQueue.async {
            if self.cameraManager.setupResult == .success {
                os_log("Shutting down the session")
                self.cameraManager.session.stopRunning()
                self.cameraManager.removeObservers()
            }
        }
        os_log("Stopping BLE scanning")
        bleCentralManager.centralManager.stopScan()
        removeObservers()
        super.viewWillDisappear(animated)
    }

    // MARK: Notifications

    func addObservers() {
        keyValueObservations.append(observe(\.bleCentralManager.centralManager.state) { _,_ in
            os_log("centralManager.state changed")
            self.bluetoothIndicator.isEnabled = (self.bleCentralManager.centralManager.state == .poweredOn)
        })
    }

    func removeObservers() {
        keyValueObservations.forEach { $0.invalidate() }
        keyValueObservations.removeAll()
    }

}

class TimedMultiClick {

    private var counter = 0

    private var countResetTimer: Timer?

    func on(count: Int, action: () -> Void, else: () -> Void) {
        countResetTimer?.invalidate()
        countResetTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in
            self.countResetTimer?.invalidate()
            self.counter = 0
        }
        counter += 1
        if counter == count {
            countResetTimer?.invalidate()
            counter = 0
            action()
        } else {
            `else`()
        }
    }

}
