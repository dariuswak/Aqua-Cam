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
        if movieFileOutput.availableVideoCodecTypes.contains(.hevc) {
            movieFileOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: movieFileOutputConnection!)
        }
        let outputFileName = uniqueID.uuidString
        let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
        movieFileOutput.startRecording(to: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
    }

    /// - Tag: DidStartRecording
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
    }

    /// - Tag: DidFinishRecording
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        if error != nil {
            print("Movie file finishing error: \(String(describing: error))")
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
                print("AVCam couldn't save the movie to your photo library: \(String(describing: error))")
            }
            self.cleanup(outputFileURL)
        })
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
