import AVFoundation
import Photos
import UIKit
import os

class MovieRecordingProcessor: NSObject, AVCaptureFileOutputRecordingDelegate {

    let uniqueID = NSUUID()

    var location: CLLocation?

    var backgroundRecordingID: UIBackgroundTaskIdentifier?

    var completionHandler: (MovieRecordingProcessor) -> Void

    init(completionHandler: @escaping (MovieRecordingProcessor) -> Void) {
        self.completionHandler = completionHandler
    }

    func startRecording(with movieFileOutput: AVCaptureMovieFileOutput) {
        if UIDevice.current.isMultitaskingSupported {
            self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        }
        let movieFileOutputConnection = movieFileOutput.connection(with: .video)
        movieFileOutputConnection?.videoOrientation = Constants.LANDSCAPE_RIGHT

        let settings = movieFileOutput.outputSettings(for: movieFileOutputConnection!)
        let newSettings: [String : Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: calculateNominalBitRate(settings),
            ],
        ]
        movieFileOutput.setOutputSettings(newSettings, for: movieFileOutputConnection!)
        os_log("Recording settings: \(movieFileOutput.outputSettings(for: movieFileOutputConnection!))")

        let outputFileName = uniqueID.uuidString
        let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
        movieFileOutput.startRecording(to: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
    }

    func calculateNominalBitRate(_ settings: [String: Any]) -> Int {
        let frameWidthFactor = settings[AVVideoWidthKey] as! Double / 1920.0
        let frameHeightFactor = settings[AVVideoHeightKey] as! Double / 1080.0
        let frameRateFactor = (settings[AVVideoCompressionPropertiesKey] as! NSDictionary)[AVVideoExpectedSourceFrameRateKey] as! Double / 60.0
        os_log("Factors: width=\(frameWidthFactor) height=\(frameHeightFactor) rate=\(frameRateFactor)")
        return Int(Constants.NOMINAL_AVG_VIDEO_BITRATE * frameWidthFactor * frameHeightFactor * frameRateFactor)
    }

    /// - Tag: DidStartRecording
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        Logger.log(.event, "record-movie-begin")
    }

    /// - Tag: DidFinishRecording
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        if error != nil {
            os_log("Movie file finishing error: \(String(describing: error))")
            Logger.log(.error, "record-movie: \(String(describing: error))")
            let success = (((error! as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as AnyObject).boolValue)!
            if !success {
                cleanup(outputFileURL)
                return
            }
        }
        PHPhotoLibrary.shared().performChanges({
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = true
            let creationRequest = PHAssetCreationRequest.forAsset()
            creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
            creationRequest.location = self.location
        }, completionHandler: { success, error in
            if !success {
                os_log("AVCam couldn't save the movie to your photo library: \(String(describing: error))")
                Logger.log(.error, "record-movie: \(String(describing: error))")
            }
            self.cleanup(outputFileURL)
        })
        Logger.log(.event, "record-movie-end")
    }

    func cleanup(_ outputFileURL: URL) {
        let path = outputFileURL.path
        if FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                os_log("Could not remove file at url: \(outputFileURL)")
            }
        }
        if let currentBackgroundRecordingID = backgroundRecordingID {
            backgroundRecordingID = UIBackgroundTaskIdentifier.invalid
            if currentBackgroundRecordingID != UIBackgroundTaskIdentifier.invalid {
                UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
            }
        }
        completionHandler(self)
    }

}
