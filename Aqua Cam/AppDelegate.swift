import UIKit
import os

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    let log = Logger()

    var window: UIWindow?

    func applicationDidBecomeActive(_ application: UIApplication) {
        os_log("Disabling sleep")
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        os_log("Enabling sleep")
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        log.start()
        return true
    }

}
