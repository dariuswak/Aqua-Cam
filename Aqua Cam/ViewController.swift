import UIKit
import AVFoundation
import Photos
import os

class ViewController: UIViewController {

    @IBOutlet weak var previewView: PreviewView!

    // MARK: Center widgets

    @IBOutlet weak var flashView: UIFlashView!

    @IBOutlet weak var focusIndicator: UIImageView!

    @IBOutlet weak var processingIndicator: UIActivityIndicatorView!

    // MARK: Top info pane

    @IBOutlet weak var topInfoPane: UIStackView!

    @IBOutlet weak var phoneBatteryIndicator: UIBatteryLevel!

    @IBOutlet weak var systemPressureIndicator: UISystemPressure!

    @IBOutlet weak var sealPressureIndicator: UILabel!

    @IBOutlet weak var depthIndicator: UILabel!

    @IBOutlet weak var timeAtDepth: TimeAtDepth!

    @IBOutlet weak var temperatureIndicator: UILabel!

    @IBOutlet weak var housingBatteryIndicator: UIBatteryLevel!

    // MARK: Bottom info pane

    @IBOutlet weak var bluetoothIndicator: UIBluetooth!

    @IBOutlet weak var modeIndicator: UIMode!

    @IBOutlet weak var cameraName: UICameraType!

    @IBOutlet weak var focusLockIndicator: UIFocus!
    
    @IBOutlet weak var stabilisationIndicator: UIStabilisationType!

    @IBOutlet weak var resolutionIndicator: UIFormatResolution!

    @IBOutlet weak var exposureIndicator: UIExposure!
    
    @IBOutlet weak var isoIndicator: UILabel!

    // MARK: Left info pane

    @IBOutlet weak var capturingLivePhotoIndicator: UILabel!

    @IBOutlet weak var recordingTime: UIRecordingTime!

    @IBOutlet weak var frameRate: UIFormatFrameRate!

    // MARK: Disconnected controls

    @IBOutlet weak var disconnectedControls: UIStackView!

    @IBAction func openSettings() {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
    }
    
    @IBAction func showDisconnectedControls() {
        disconnectedControls.isHidden = false
    }

    // take photo
    // start/stop recording video
    // wake up
    @IBAction func shutterButtonPressed() {
        if !cameraManager.session.isRunning {
            wakeup()
            return
        }
        if (cameraManager.movieFileOutput != nil) {
            os_log("Toggling video recording")
            cameraManager.toggleMovieRecording(flashView)
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

    func wakeup() {
        cameraManager.startSession {
            let connected = self.bleCentralManager.discoveredPeripheral?.state == .connected
            self.previewView.isHidden = false
            self.disconnectedControls.isHidden = connected
            self.topInfoPane.isHidden = !connected
        }
    }

    func sleep() {
        previewView.isHidden = true
        cameraManager.shutdownSession()
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
            let isPhoto = cameraManager.cyclePhotoAndVideo() == .photo
            recordingTime.show(if: !isPhoto) {
                self.frameRate.isHidden = isPhoto
            }
            modeIndicator.isPhoto = isPhoto
        }
    }

    // 3rd button - up
    // change camera/format
    @IBAction func upButtonPressed() {
        if cameraName.selected {
            cameraManager.configureSession(changeCamera: .previous, changeFormat: .current)
        } else {
            cameraManager.configureSession(changeCamera: .current, changeFormat: .previous)
        }
    }

    // 4th button - menu/ok
    // select change camera/format (cycle)
    @IBAction func menuButtonPressed() {
        UIView.transition(with: resolutionIndicator.superview!,
                          duration: 0.5,
                          options: .layoutSubviews) {
            let wasCameraNameSelected = self.cameraName.selected
            self.cameraName.selected = !wasCameraNameSelected
            self.resolutionIndicator.selected = wasCameraNameSelected
        }
    }

    // 5th button - down
    // change camera/format
    @IBAction func downButtonPressed() {
        if cameraName.selected {
            cameraManager.configureSession(changeCamera: .next, changeFormat: .current)
        } else {
            cameraManager.configureSession(changeCamera: .current, changeFormat: .next)
        }
    }

    @objc let cameraManager = CameraManager()

    @objc let bleCentralManager = BleCentralManager()

    @objc let sensorManager = SensorManager()

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
        permissionsManager.askForSensorPermissions(sensorManager)

        cameraManager.preconfigureSession(previewView: previewView)

        cameraName.selected = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        switch cameraManager.setupResult {
        case .success:
            cameraManager.startSession()
        case .notAuthorizedCamera:
            os_log("Alert about camera permissions")
            alert(message: "Permission to use the camera is denied, please review settings", comment: "Alert message when no camera access")
        case .notAuthorizedAlbum:
            os_log("Alert about photos permissions")
            alert(message: "Permission to save to album is denied, please review settings", comment: "Alert message when no album access")
        case .configurationFailed:
            os_log("Alert about configuration failure")
            alert(message: "Unable to capture media", comment:"Alert message when something goes wrong during capture session configuration")
        }
        addObservers()
    }

    override func viewWillDisappear(_ animated: Bool) {
        cameraManager.shutdownSession()
        os_log("Stopping BLE scanning")
        bleCentralManager.centralManager.stopScan()
        removeObservers()
        super.viewWillDisappear(animated)
    }

    func alert(message: String, comment: String) {
        DispatchQueue.main.async {
            let localizedMessage = NSLocalizedString(message, comment: comment)
            let alertController = UIAlertController(title: Bundle.main.appName, message: localizedMessage, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                    style: .`default`,
                                                    handler: { _ in self.openSettings() }))
            self.present(alertController, animated: true, completion: nil)
        }
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
        if self.cameraManager.videoDeviceInput != nil {
            self.resolutionIndicator.fromFormat = self.cameraManager.videoDeviceInput.device.activeFormat
        }
        // phone battery level
        NotificationCenter.default.addObserver(self,
                                      selector:#selector(batteryLevelChanged),
                                          name:UIDevice.batteryLevelDidChangeNotification,
                                        object:nil)
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevelChanged(notification: NSNotification(name: UIDevice.batteryLevelDidChangeNotification, object: nil))
        // system pressure
        keyValueObservations.append(observe(\.cameraManager.videoDeviceInput?.device.systemPressureState) { _,_ in
            self.systemPressureIndicator.level = self.cameraManager.videoDeviceInput.device.systemPressureState.level
        })
        if self.cameraManager.videoDeviceInput != nil {
            self.systemPressureIndicator.level = self.cameraManager.videoDeviceInput.device.systemPressureState.level
        }
        // seal pressure
        keyValueObservations.append(observe(\.sensorManager.pressure) { _,_ in
            DispatchQueue.main.async {
                self.sealPressureIndicator.text = String(self.sensorManager.pressure)
                self.sealPressureIndicator.superview?.isHidden = false
            }
        })
        // depth & time at depth
        keyValueObservations.append(observe(\.bleCentralManager.depthSensor) { _,_ in
            self.depthIndicator.text = " \(self.bleCentralManager.depthSensor)m "
            self.depthIndicator.isHidden = false
            self.timeAtDepth.depth = self.bleCentralManager.depthSensor
        })
        // temperature
        keyValueObservations.append(observe(\.bleCentralManager.temperatureSensor) { _,_ in
            self.temperatureIndicator.text = " \(self.bleCentralManager.temperatureSensor)℃ "
        })
        // housing battery level
        keyValueObservations.append(observe(\.bleCentralManager.batteryLevelPercentage) { _,_ in
            self.housingBatteryIndicator.batteryLevel = self.bleCentralManager.batteryLevelPercentage
        })
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
        if self.cameraManager.videoDeviceInput != nil {
            self.cameraName.cameraType = self.cameraManager.videoDeviceInput.device.deviceType
        }
        // focus lock
        keyValueObservations.append(observe(\.cameraManager.videoDeviceInput.device.focusMode) { _,_ in
            DispatchQueue.main.async {
                self.focusLockIndicator.focusMode = self.cameraManager.videoDeviceInput.device.focusMode
            }
        })
        if self.cameraManager.videoDeviceInput != nil {
            self.focusLockIndicator.focusMode = self.cameraManager.videoDeviceInput.device.focusMode
        }
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
        // disconnected controls & connected functions
        keyValueObservations.append(observe(\.bleCentralManager.discoveredPeripheral?.state) { _,_ in
            switch self.bleCentralManager.discoveredPeripheral?.state {
            case .connected, .disconnected: break
            default: return // ignore transition states
            }
            let connected = self.bleCentralManager.discoveredPeripheral?.state == .connected
            let awake = self.cameraManager.session.isRunning
            self.topInfoPane.show(if: connected && awake, duration: 1, options: .transitionCrossDissolve)
            self.bluetoothIndicator.connected = connected
            UIScreen.main.brightness = connected ? 1 : 0.5
            if connected {
                self.disconnectedControls.show(if: false, duration: 1, options: .transitionCrossDissolve)
            }
            if connected && !awake {
                self.wakeup()
            }
            if !connected && awake {
                self.sleep()
                self.menuButtonPressed() // compensate for the most typical scenario when disconnected using the Menu Button;
                                         // in such case the button press effect should be reverted
            }
        })
        NotificationCenter.default.addObserver(self,
                                      selector:#selector(brightnessChanged),
                                          name:UIScreen.brightnessDidChangeNotification,
                                        object:nil)
        self.disconnectedControls.isHidden = self.cameraManager.videoDeviceInput == nil
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
        NotificationCenter.default.removeObserver(self)
        keyValueObservations.forEach { $0.invalidate() }
        keyValueObservations.removeAll()
    }

    @objc
    func batteryLevelChanged(notification: NSNotification) {
        os_log("Phone Battery level changed to: \(UIDevice.current.batteryLevel)")
        Logger.log(.camera_battery, Int(UIDevice.current.batteryLevel * 100))
        // 20% is effectively 0%: the system warning will show & the app will enter background & the phone will sleep
        let adjustedLevel = (UIDevice.current.batteryLevel - 0.2) * 125
        phoneBatteryIndicator.batteryLevel = Int(adjustedLevel)
    }

    @objc
    func brightnessChanged(notification: NSNotification) {
        let connected = bleCentralManager.discoveredPeripheral?.state == .connected
        if connected {
            os_log("Resetting brightness to max from \(UIScreen.main.brightness)")
            Logger.log(.event, "brightness-reset")
            UIScreen.main.brightness = 1
        }
    }

}
