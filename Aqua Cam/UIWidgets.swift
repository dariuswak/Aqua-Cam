import UIKit
import AVFoundation
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

class UIMode: UILabel {

    var isPhoto: Bool = true {
        didSet {
            text = isPhoto ? " PHOTO|" : " VIDEO|"
        }
    }

}

class UICameraType: UILabel {

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

class UIFormatResolution: UILabel {

    var fromFormat: AVCaptureDevice.Format? {
        didSet {
            let dimensions = fromFormat!.formatDescription.dimensions
            switch dimensions.height {
            case 720:
                text = " 2/3 HD "
            case 1080:
                text = " HD "
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
            text = " 1/\(Int(Int64(exposureDuration!.timescale) / exposureDuration!.value)) "
        }
    }

}
