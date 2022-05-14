import UIKit
import os

class Logger {

    static let dateFormatter = DateFormatter()

    var logFlushTimer: Timer?

    static func log(_ message: String, _ data: Any) {
        print("\(Logger.dateFormatter.string(from: Date()))\t\(message)\t\(data)")
    }

    func start() {
        Logger.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        Logger.dateFormatter.timeZone = TimeZone.autoupdatingCurrent
        redirectStdOut()
        logFlushTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            fflush(__stdoutp)
        }
        logFlushTimer!.tolerance = 3
    }

    func redirectStdOut() {
        if isatty(STDOUT_FILENO) == 1 {
            // not for debug run
            return
        }
        let documentsLocation = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let logsLocation = documentsLocation + "/logs"
        if !FileManager().fileExists(atPath: logsLocation) {
            do {
                try FileManager().createDirectory(atPath: logsLocation, withIntermediateDirectories: false)
            } catch {
                os_log("Could prepare logs location: \(logsLocation), error: \(String(describing: error))")
                return
            }
        }
        let timestampPath = Logger.dateFormatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let logFilePath = logsLocation + "/aqua_cam-\(timestampPath).log"
        os_log("Redirecting stdout to \(logFilePath)")
        freopen(logFilePath.cString(using: String.Encoding.ascii)!, "a+", stdout)
    }

}
