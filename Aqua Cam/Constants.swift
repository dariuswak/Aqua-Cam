import UIKit
import AVFoundation

class Constants {

    static let LANDSCAPE_RIGHT: AVCaptureVideoOrientation = .landscapeRight

    // for HD 60fps (default ~11 Mbps)
    static let NOMINAL_AVG_VIDEO_BITRATE = 25_000_000.0

    enum Direction: Int {
        case next = 1
        case previous = -1
        case current = 0
    }

    static let CAMERAS: [AVCaptureDevice.DeviceType] = [
        .builtInWideAngleCamera,
        .builtInUltraWideCamera,
        .builtInLiDARDepthCamera,
        .builtInTelephotoCamera,
    ]

    static let FORMATS: [FormatDescription] = [
        FormatDescription(type: .FOUR_K, dimensions: CMVideoDimensions(width: 4032, height: 3024), frameRate: 30, supportsDepthData: false),
        FormatDescription(type: .UHD, dimensions: CMVideoDimensions(width: 3840, height: 2160)),
        FormatDescription(type: .HD_4_3, dimensions: CMVideoDimensions(width: 1920, height: 1440)),
        FormatDescription(type: .HD_SLOMO, dimensions: CMVideoDimensions(width: 1920, height: 1080), frameRate: 120),
        FormatDescription(type: .HD, dimensions: CMVideoDimensions(width: 1920, height: 1080)),
    ]

}

enum FormatType: Int, CaseIterable {
    case FOUR_K
    case UHD
    case HD_4_3
    case HD_SLOMO
    case HD
}

class FormatDescription {

    let type: FormatType

    let dimensions: CMVideoDimensions

    let frameRate: Float64

    let supportsDepthData: Bool

    init(type: FormatType,
         dimensions: CMVideoDimensions,
         frameRate: Float64 = 60,
         supportsDepthData: Bool = true
    ) {
        self.type = type
        self.dimensions = dimensions
        self.frameRate = frameRate
        self.supportsDepthData = supportsDepthData
    }

    static func of(_ formatType: FormatType) -> FormatDescription {
        return Constants.FORMATS.first { $0.type == formatType }!
    }

}
