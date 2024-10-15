import UIKit
import AVFoundation
import CoreBluetooth
import os

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

class UIFlashView: UIView {

    func flash(color: UIColor) {
        DispatchQueue.main.async {
            self.backgroundColor = color
            UIView.animate(withDuration: 0.5) {
                self.backgroundColor = UIColor.clear
            }
        }
    }

}

class UIRecordingTime: UILabel {

    private static let ZERO = " 0s "

    private let format = DateComponentsFormatter()

    private var timer: Timer?

    private var startTime: Date?

    var isRecording: Bool = false {
        didSet {
            if isRecording {
                text = UIRecordingTime.ZERO
                startTime = Date.now
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    self.text = " \(self.format.string(from: self.startTime!, to: Date.now) ?? "(err)")s "
                    self.flashBorder()
                }
                timer?.tolerance = 0.1
            } else {
                timer?.invalidate()
            }
            DispatchQueue.main.async {
                self.isEnabled = self.isRecording
            }
        }
    }

    override var isHidden: Bool {
        willSet {
            text = UIRecordingTime.ZERO
            timer?.invalidate()
        }
    }

    func flashBorder() {
        DispatchQueue.main.async {
            self.layer.borderWidth = 5
            self.layer.borderColor = UIColor.red.cgColor
            UIView.transition(with: self, duration: 0.5, options: .curveEaseIn) {
                self.layer.borderWidth = 0
            }
        }
    }

}

class UIFormatFrameRate: UILabel {

    var fromFormat: AVCaptureDevice.Format? {
        didSet {
            text = " \(Int(fromFormat!.videoSupportedFrameRateRanges.last!.maxFrameRate))"
        }
    }

    override var isHidden: Bool {
        didSet {
            self.superview?.isHidden = isHidden
        }
    }

}

class UIBatteryLevel: UIStackView {

    lazy var icon = self.subviews[1] as! UIImageView

    lazy var percentage = self.subviews[2] as! UILabel

    var batteryLevel: Int = 0 {
        didSet {
            DispatchQueue.main.async {
                self.icon.image = switch self.batteryLevel {
                    case ..<13: UIImage.battery0
                    case ..<38: UIImage.battery25
                    case ..<63: UIImage.battery50
                    case ..<88: UIImage.battery75
                    case ...100: UIImage.battery100
                    default: UIImage.questionMarkCircle
                }
                self.percentage.text = "\(self.batteryLevel)% "
            }
        }
    }

}

class UISystemPressure: UIImageView {

    var level: AVCaptureDevice.SystemPressureState.Level = .nominal {
        didSet {
            os_log("System pressure changed to: \(self.level.rawValue)")
            DispatchQueue.main.async {
                self.image = switch self.level {
                    case .nominal: UIImage.sunMax
                    case .fair: UIImage.cloudSun
                    case .serious: UIImage.cloud
                    case .critical: UIImage.cloudHeavyRain
                    case .shutdown: UIImage.cloudBolt
                    default: UIImage.questionMarkCircle
                }
            }
        }
    }

}

class TimeAtDepth: UIRecordingTime {

    var depth: Float = 0 {
        didSet {
            if self.isRecording {
                if depth == 0 {
                    self.isRecording = false
                }
            } else if depth > Constants.TIME_AT_DEPTH_THRESHOLD {
                self.isHidden = false
                self.isRecording = true
            }
        }
    }

    override func flashBorder() {
        // do not flash
    }

}

class UIBluetooth: UIImageView {

    var state: CBManagerState = .unknown {
        didSet {
            let poweredOn = state == .poweredOn
            image = poweredOn ? UIImage.bluetooth : UIImage.bluetoothDisabled
            tintColor = poweredOn ? Colour.BLUETOOTH : Colour.INACTIVE
        }
    }

    var connected: Bool = false {
        didSet {
            if connected {
                image = UIImage.bluetoothConnected
            } else {
                (state = state)
            }
        }
    }

}

class UIMode: UILabel {

    var isPhoto: Bool = true {
        didSet {
            text = isPhoto ? " PHOTO|" : " VIDEO|"
        }
    }

}

class UICameraType: SelectableUILabel {

    var cameraType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera {
        didSet {
            let longName = cameraType.rawValue
            os_log("Camera name: \(longName)")
            self.text = switch longName {
                case let name where name.contains("WideAngle"): " W "
                case let name where name.contains("UltraWide"): " U "
                case let name where name.contains("Telephoto"): " T "
                default: " ? "
            }
        }
    }

}

class UIFocus: UIImageView {

    var focusIndicator: UIImageView?

    var focusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus {
        didSet {
            tintColor = Colour.activeIf(focusMode == .locked)
            if focusMode == .autoFocus {
                UIView.animate(withDuration: 0.2) {
                    self.focusIndicator?.alpha = 1
                }
            } else {
                UIView.animate(withDuration: 1.5) {
                    self.focusIndicator?.alpha = 0
                }
            }
        }
    }

}

class UIStabilisationType: UILabel {

    func setStabilisationType(connection: AVCaptureConnection?) {
        os_log("Stabilisation mode: \(connection?.isVideoStabilizationSupported ?? false) / \(connection?.activeVideoStabilizationMode.rawValue ?? -100)")
        guard let stabilisationMode = connection?.activeVideoStabilizationMode else { return }
        isEnabled = stabilisationMode != .off
        text = switch stabilisationMode {
            case .off: " (x) "
            case .standard, .cinematic: " (o) "
            case .cinematicExtended, .cinematicExtendedEnhanced: " ((o)) "
            default: " (?) "
        }
    }

}

class UIFormatResolution: SelectableUILabel {

    var fromFormat: AVCaptureDevice.Format? {
        didSet {
            let dimensions = fromFormat!.formatDescription.dimensions
            text = switch dimensions.height {
                case 1080: " HD "
                case 1440: " HD 4/3 "
                case 2160: " UHD "
                case 3024: " 4K " // should be 3072, but is slightly smaller
                default: " \(dimensions.width)x\(dimensions.height) "
            }
        }
    }

}

class UIExposure: UILabel {

    var exposureDuration: CMTime? {
        didSet {
            guard let exposureDuration = exposureDuration, exposureDuration.value != 0
                    else {
                        text = " 1/? "
                        return
                    }
            text = " 1/\(Int(Int64(exposureDuration.timescale) / exposureDuration.value)) "
        }
    }

}

class SelectableUILabel: UILabel {

    var selected: Bool = false {
        didSet {
            layer.borderWidth = selected ? 2 : 0
            layer.masksToBounds = selected
            layer.borderColor = Colour.ACTIVE.cgColor
            layer.cornerRadius = 8
        }
    }

}
