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
            UIView.animate(withDuration: 0.35) {
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
                }
                timer?.tolerance = 3
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
                let imageName: String
                switch self.batteryLevel {
                case 0..<13: imageName = "battery.0"
                case 13..<38: imageName = "battery.25"
                case 38..<63: imageName = "battery.50"
                case 63..<88: imageName = "battery.75"
                case 88...100: imageName = "battery.100"
                default: imageName = "questionmark.circle"
                }
                self.icon.image = UIImage(systemName: imageName)
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
                let imageName: String
                switch self.level {
                case .nominal: imageName = "sun.max"
                case .fair: imageName = "cloud.sun"
                case .serious: imageName = "cloud"
                case .critical: imageName = "cloud.heavyrain"
                case .shutdown: imageName = "cloud.bolt"
                default: imageName = "questionmark.circle"
                }
                self.image = UIImage(systemName: imageName)
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

}

class UIBluetooth: UIImageView {

    var state: CBManagerState = .unknown {
        didSet {
            let poweredOn = state == .poweredOn
            image = poweredOn ? UIImage(named: "bluetooth") : UIImage(named: "bluetooth_disabled")
            tintColor = poweredOn ? Colour.BLUETOOTH : Colour.INACTIVE
        }
    }

    var connected: Bool = false {
        didSet {
            if connected {
                image = UIImage(named: "bluetooth_connected")
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
            let codeName = (longName.contains("Ultra") ? "U" : "") +
                           (longName.contains("Wide") ? "W" : "") +
                           (longName.contains("Tele") ? "T" : "") +
                           (longName.contains("Depth") ? "D" : "")
            self.text = " \(codeName) "
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
        let indicatorText: String = { switch stabilisationMode {
            case .off, .standard: return " (o) "
            case .cinematic, .cinematicExtended: return " ((o)) "
            default: return " (?) "
        }}()
        text = indicatorText
    }

}

class UIFormatResolution: SelectableUILabel {

    var fromFormat: AVCaptureDevice.Format? {
        didSet {
            let dimensions = fromFormat!.formatDescription.dimensions
            switch dimensions.height {
            case 720:
                text = " 2/3 HD "
            case 1080:
                text = " HD "
            case 1440:
                text = " HD 4/3 "
            case 2160:
                text = " UHD "
            case 3024: // should be 3072, but is slightly smaller
                text = " 4K "
            default:
                text = " \(dimensions.width)x\(dimensions.height) "
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
            layer.borderColor = Colour.ACTIVE.cgColor
            layer.cornerRadius = 8
        }
    }

}
