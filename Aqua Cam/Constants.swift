import UIKit
import AVFoundation

class Constants {

    static let LANDSCAPE_RIGHT: AVCaptureVideoOrientation = .landscapeRight

    static let HD_4K: AVCaptureSession.Preset = .hd4K3840x2160

    // for HD 60fps (default ~11 Mbps)
    static let NOMINAL_AVG_VIDEO_BITRATE = 25_000_000.0

    enum Direction: Int {
        case next = 1
        case previous = -1
        case last = 0
    }

}
