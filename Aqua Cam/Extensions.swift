import Foundation
import UIKit

extension Bundle {

    var appName: String {
        return object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? object(forInfoDictionaryKey: "CFBundleName") as! String
    }

}

extension UIView {

    func show(if shouldShow: Bool,
              duration: TimeInterval = 0.5,
              options: UIView.AnimationOptions = .layoutSubviews,
              extraAnimations: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            UIView.transition(with: self.superview!,
                              duration: duration,
                              options: options) {
                self.isHidden = !shouldShow
                extraAnimations?()
            }
        }
    }

}

@available(iOS, deprecated: 19, message: "It's that time of year — check for system symbols deprecations, update test with new members.")
extension UIImage {

    static let questionMarkCircle = UIImage(systemName: "questionmark.circle")!

    static let battery0 = UIImage(systemName: "battery.0percent")!
    static let battery25 = UIImage(systemName: "battery.25percent")!
    static let battery50 = UIImage(systemName: "battery.50percent")!
    static let battery75 = UIImage(systemName: "battery.75percent")!
    static let battery100 = UIImage(systemName: "battery.100percent")!

    static let sunMax = UIImage(systemName: "sun.max")!
    static let cloudSun = UIImage(systemName: "cloud.sun")!
    static let cloud = UIImage(systemName: "cloud")!
    static let cloudHeavyRain = UIImage(systemName: "cloud.heavyrain")!
    static let cloudBolt = UIImage(systemName: "cloud.bolt")!

}
