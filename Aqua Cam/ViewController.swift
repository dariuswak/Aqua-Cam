import UIKit
import AVFoundation
import Photos
import os

class ViewController: UIViewController {

    @IBOutlet weak var previewView: PreviewView!

    @IBOutlet weak var disconnectedControls: UIView!

    // MARK: Center widgets

    @IBOutlet weak var flashView: UIFlashView!

    @IBOutlet weak var focusIndicator: UIImageView!

    @IBOutlet weak var processingIndicator: UIActivityIndicatorView!

    // MARK: Left info pane

    @IBOutlet weak var capturingLivePhotoIndicator: UILabel!

    @IBOutlet weak var recordingTime: UIRecordingTime!

    @IBOutlet weak var frameRate: UIFormatFrameRate!

    // MARK: Bottom info pane

    @IBOutlet weak var bluetoothIndicator: UIBluetooth!

    @IBOutlet weak var modeIndicator: UIMode!

    @IBOutlet weak var cameraName: UICameraType!

    @IBOutlet weak var focusLockIndicator: UIFocus!
    
    @IBOutlet weak var stabilisationIndicator: UIStabilisationType!

    @IBOutlet weak var resolutionIndicator: UIFormatResolution!

    @IBOutlet weak var exposureIndicator: UIExposure!
    
    @IBOutlet weak var isoIndicator: UILabel!

    // MARK: Disconnected controls

    @IBAction func openSettings() {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
    }

    // take photo
    // start/stop recording video
    // wake up
    @IBAction func shutterButtonPressed() {
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
                    self.disconnectedControls.isHidden = self.bleCentralManager.discoveredPeripheral?.state == .connected
                    os_log("Wakeup from sleep finished")
                }
            }
            return
        }
        if (cameraManager.movieFileOutput != nil) {
            os_log("Toggling video recording")
            cameraManager.toggleMovieRecording(self.flashView)
        } else {
            os_log("Capturing photo")
            cameraManager.capturePhoto(viewController: self)
        }
    }
    
    // 1st button - focus
    // hold / triple click - sleep (shutter to wake)
    @IBAction func focusButtonPressed() {
        multiClick.on(count: 3) {
            sleep()
        } else: {
            os_log("Locking focus and exposure")
            cameraManager.lockFocusAndExposureInCentre()
        }
    }

    func sleep() {
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
    }

    // 2nd button - mode
    // photo/video (cycle)
    // click during video recording - take photo
    @IBAction func modeButtonPressed() {
        if cameraManager.movieFileOutput?.isRecording == true {
            os_log("Capturing photo during movie recording")
            cameraManager.capturePhoto(viewController: self)
        } else {
            os_log("Changing mode: photo/video")
            let isPhoto = self.cameraManager.cyclePhotoAndVideo() == .photo
            self.recordingTime.show(if: !isPhoto) {
                self.frameRate.isHidden = isPhoto
            }
            self.modeIndicator.isPhoto = isPhoto
        }
    }

    // 3rd button - up
    // change camera/format
    @IBAction func upButtonPressed() {
        cameraManager.sessionQueue.async {
            self.cameraManager.changeFormat(direction: .previous)
        }
    }

    // 4th button - menu/ok
    // change camera (cycle)
    @IBAction func menuButtonPressed() {
        os_log("Changing camera (cycle)")
        cameraManager.sessionQueue.async {
            self.cameraManager.changeCamera()
        }
    }

    // 5th button - down
    // change camera/format
    @IBAction func downButtonPressed() {
        cameraManager.sessionQueue.async {
            self.cameraManager.changeFormat(direction: .next)
        }
    }

    @objc let cameraManager = CameraManager()

    @objc let bleCentralManager = BleCentralManager()

    let permissionsManager = PermissionsManager()

    let multiClick = TimedMultiClick()

    var keyValueObservations = [NSKeyValueObservation]()

    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        focusLockIndicator.focusIndicator = focusIndicator
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
        // recording timer
        keyValueObservations.append(observe(\.cameraManager.movieFileOutput?.isRecording) { _,_ in
            self.recordingTime.isRecording = self.cameraManager.movieFileOutput?.isRecording ?? false
        })
        // format info
        keyValueObservations.append(observe(\.cameraManager.videoDeviceInput?.device.activeFormat) { _,_ in
            let format = self.cameraManager.videoDeviceInput.device.activeFormat
            DispatchQueue.main.async {
                self.frameRate.fromFormat = format
                self.resolutionIndicator.fromFormat = format
            }
        })
        self.resolutionIndicator.fromFormat = self.cameraManager.videoDeviceInput.device.activeFormat
        // bluetooth on/off
        keyValueObservations.append(observe(\.bleCentralManager.centralManager.state) { _,_ in
            DispatchQueue.main.async {
                self.bluetoothIndicator.state = self.bleCentralManager.centralManager.state
            }
        })
        self.bluetoothIndicator.state = self.bleCentralManager.centralManager.state
        // camera type
        keyValueObservations.append(observe(\.cameraManager.videoDeviceInput.device.deviceType) { _,_ in
            DispatchQueue.main.async {
                self.cameraName.cameraType = self.cameraManager.videoDeviceInput.device.deviceType
            }
        })
        self.cameraName.cameraType = self.cameraManager.videoDeviceInput.device.deviceType
        // focus lock
        keyValueObservations.append(observe(\.cameraManager.videoDeviceInput.device.focusMode) { _,_ in
            DispatchQueue.main.async {
                self.focusLockIndicator.focusMode = self.cameraManager.videoDeviceInput.device.focusMode
            }
        })
        self.focusLockIndicator.focusMode = self.cameraManager.videoDeviceInput.device.focusMode
        // stabilisation mode
        keyValueObservations.append(observe(\.cameraManager.videoConnection?.activeVideoStabilizationMode) { _,_ in
            DispatchQueue.main.async {
                self.stabilisationIndicator.setStabilisationType(connection: self.cameraManager.videoConnection)
            }
        })
        self.stabilisationIndicator.setStabilisationType(connection: self.cameraManager.videoConnection)
        // exposure
        keyValueObservations.append(observe(\.cameraManager.videoDeviceInput.device.exposureDuration) { _,_ in
            DispatchQueue.main.async {
                self.exposureIndicator.exposureDuration = self.cameraManager.videoDeviceInput.device.exposureDuration
            }
        })
        // iso
        keyValueObservations.append(observe(\.cameraManager.videoDeviceInput.device.iso) { _,_ in
            DispatchQueue.main.async {
                self.isoIndicator.text = " ISO \(Int(self.cameraManager.videoDeviceInput.device.iso)) "
            }
        })
        // disconnected view
        keyValueObservations.append(observe(\.bleCentralManager.discoveredPeripheral?.state) { _,_ in
            let connected = self.bleCentralManager.discoveredPeripheral?.state == .connected
            let shouldHide = connected || self.previewView.isHidden
            self.disconnectedControls.show(if: !shouldHide, duration: 1, options: .transitionCrossDissolve)
            self.bluetoothIndicator.connected = connected
        })
        // housing buttons
        keyValueObservations.append(observe(\.bleCentralManager.buttonPressed) { _,_ in
            switch self.bleCentralManager.buttonPressed {
            case BleConstants.shutterButtonCode: self.shutterButtonPressed()
            case BleConstants.focusButtonCode: self.focusButtonPressed()
            case BleConstants.focusPressHoldButtonCode: self.sleep()
            case BleConstants.modeButtonCode: self.modeButtonPressed()
            case BleConstants.upButtonCode: self.upButtonPressed()
            case BleConstants.menuButtonCode: self.menuButtonPressed()
            case BleConstants.downButtonCode: self.downButtonPressed()
            default: os_log("Unsupported button code: \(self.bleCentralManager.buttonPressed)")
            }
        })
    }

    func removeObservers() {
        keyValueObservations.forEach { $0.invalidate() }
        keyValueObservations.removeAll()
    }

}
