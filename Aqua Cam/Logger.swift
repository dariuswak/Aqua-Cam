import UIKit
import os

class Logger {

    enum Column: Int, CaseIterable {
        case timestamp, depth, temp, housing_battery, camera_battery, event, error
    }

    static let dateFormatter = DateFormatter()

    static let indent = (0 ..< Column.allCases.count)
        .map({_ in "\t"})
        .joined()

    var logFlushTimer: Timer?

    static func log(_ column: Column, _ data: Any) {
        print("\(Logger.dateFormatter.string(from: Date()))\(indent.prefix(column.rawValue))\(data)")
    }

    func start() {
        Logger.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        Logger.dateFormatter.timeZone = TimeZone.autoupdatingCurrent
        redirectStdOut()
        print(Column.allCases
            .map({"\($0)"})
            .joined(separator: "\t")
        )
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
        let logFilePath = logsLocation + "/aqua_cam-\(timestampPath).csv"
        os_log("Redirecting stdout to \(logFilePath)")
        freopen(logFilePath.cString(using: String.Encoding.ascii)!, "a+", stdout)
    }

}
