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
