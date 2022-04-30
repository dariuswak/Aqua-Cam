import UIKit
import AVFoundation
import Photos
import os

class ViewController: UIViewController {

    @IBOutlet weak var previewView: PreviewView!

    @IBOutlet weak var disconnectedControls: UIView!

    @IBOutlet weak var capturingLivePhotoIndicator: UIButton!

    @IBOutlet weak var processingIndicator: UIActivityIndicatorView!

    @IBOutlet weak var focusIndicator: UIImageView!

    @IBOutlet weak var recordingTime: UILabel!

    @IBOutlet weak var bluetoothIndicator: UIButton!

    @IBOutlet weak var housingProximity: UIProgressView!
    
    @IBAction func openSettings() {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                  options: [:],
                                  completionHandler: nil)
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
    // hold / triple click - sleep (shutter to wake)
    @IBAction func focusButtonPressed() {
        multiClick.on(count: 3) {
            sleep()
        } else: {
            os_log("Locking focus and exposure (cycle)")
            cameraManager.cycleLockFocusAndExposureInCentre(viewController: self)
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
    // click - change camera (cycle)
    // double click - photo/video (cycle)
    // click during video recording - take photo
    @IBAction func modeButtonPressed() {
        if cameraManager.movieFileOutput?.isRecording == true {
            os_log("Capturing photo during movie recording")
            cameraManager.capturePhoto(previewView: previewView, viewController: self)
        } else {
            multiClick.on(count: 2) {
                os_log("Changing mode: photo/video")
                self.recordingTime.isHidden = self.cameraManager.cyclePhotoAndVideo() == .photo
            } else: {
                os_log("Changing camera (cycle)")
                cameraManager.sessionQueue.async {
                    self.cameraManager.changeCamera()
                }
            }
        }
    }

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
        keyValueObservations.append(observe(\.bleCentralManager.discoveredPeripheral?.state) { _,_ in
            let connected = self.bleCentralManager.discoveredPeripheral?.state == .connected
            UIView.animate(withDuration: 1, animations: {
                self.disconnectedControls.alpha = connected ? 0 : 1
            }, completion: { _ in
                self.disconnectedControls.isHidden = connected
            })
        })
        keyValueObservations.append(observe(\.bleCentralManager.centralManager.isScanning) { _,_ in
            self.housingProximity.isHidden = !self.bleCentralManager.centralManager.isScanning
        })
        keyValueObservations.append(observe(\.bleCentralManager.signalStrengthDb) { _,_ in
            let current = self.bleCentralManager.signalStrengthDb
            self.housingProximity.setProgress(self.calculateProgress(current), animated: true)
            self.housingProximity.trackTintColor = (current > SignalStrength.closingUp.rawValue ? UIColor.systemRed : .none)
        })
        keyValueObservations.append(observe(\.bleCentralManager.buttonPressed) { _,_ in
            switch self.bleCentralManager.buttonPressed {
            case BleConstants.shutterButtonCode: self.shutterButtonPressed()
            case BleConstants.focusButtonCode: self.focusButtonPressed()
            case BleConstants.focusPressHoldButtonCode: self.sleep()
            case BleConstants.modeButtonCode: self.modeButtonPressed()
            case BleConstants.upButtonCode: break
            case BleConstants.menuButtonCode: break
            case BleConstants.downButtonCode: break
            default: os_log("Unsupported button code: \(self.bleCentralManager.buttonPressed)")
            }
        })
    }

    // convert strength in (minimal..connectable) into (0..1)
    // range     = -80 .. -40 = 40 = -(minimal - connectable)
    // proximity = -55 .. -40 = 15 = -(strength - connectable)
    // progress  = 1 - 15/40  = 1 - (proximity / range)
    func calculateProgress(_ current: Int) -> Float {
        let range = -(SignalStrength.minimal.rawValue - SignalStrength.connectable.rawValue)
        let proximity = -(current - SignalStrength.connectable.rawValue)
        return 1 - (Float(proximity) / Float(range))
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
