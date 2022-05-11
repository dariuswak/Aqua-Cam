import AVFoundation
import Photos
import os

class PhotoCaptureProcessor: NSObject {

    let perceptualColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    let requestedPhotoSettings: AVCapturePhotoSettings

    let willCapturePhotoAnimation: () -> Void

    let livePhotoCaptureHandler: (Bool) -> Void

    let completionHandler: (PhotoCaptureProcessor) -> Void

    let photoProcessingHandler: (Bool) -> Void

    lazy var context = CIContext()

    var uniqueID: Int64 { get {
        return requestedPhotoSettings.uniqueID
    }}

    var photoData: Data?

    var depthData: Data?

    var livePhotoCompanionMovieURL: URL?

    var maxPhotoProcessingTime: CMTime?

    var location: CLLocation?

    init(with requestedPhotoSettings: AVCapturePhotoSettings,
         willCapturePhotoAnimation: @escaping () -> Void,
         livePhotoCaptureHandler: @escaping (Bool) -> Void,
         completionHandler: @escaping (PhotoCaptureProcessor) -> Void,
         photoProcessingHandler: @escaping (Bool) -> Void) {
        self.requestedPhotoSettings = requestedPhotoSettings
        self.willCapturePhotoAnimation = willCapturePhotoAnimation
        self.livePhotoCaptureHandler = livePhotoCaptureHandler
        self.completionHandler = completionHandler
        self.photoProcessingHandler = photoProcessingHandler
    }

    func didFinish() {
        if let livePhotoCompanionMoviePath = livePhotoCompanionMovieURL?.path {
            if FileManager.default.fileExists(atPath: livePhotoCompanionMoviePath) {
                do {
                    try FileManager.default.removeItem(atPath: livePhotoCompanionMoviePath)
                } catch {
                    print("Could not remove file at url: \(livePhotoCompanionMoviePath)")
                }
            }
        }
        completionHandler(self)
    }
}

extension PhotoCaptureProcessor: AVCapturePhotoCaptureDelegate {

    static let ONE_SECOND = CMTime(seconds: 1, preferredTimescale: 1)

    /// - Tag: WillBeginCapture
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        if resolvedSettings.livePhotoMovieDimensions.width > 0 && resolvedSettings.livePhotoMovieDimensions.height > 0 {
            livePhotoCaptureHandler(true)
        }
        maxPhotoProcessingTime = resolvedSettings.photoProcessingTimeRange.start + resolvedSettings.photoProcessingTimeRange.duration
    }

    /// - Tag: WillCapturePhoto
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        willCapturePhotoAnimation()
        guard let maxPhotoProcessingTime = maxPhotoProcessingTime else { return }
        if maxPhotoProcessingTime > PhotoCaptureProcessor.ONE_SECOND {
            photoProcessingHandler(true)
        }
    }

    /// - Tag: DidFinishProcessingPhoto
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        photoProcessingHandler(false)
        if let error = error {
            os_log("Error capturing photo: \(String(describing: error))")
            return
        } else {
            photoData = photo.fileDataRepresentation()
        }
        guard var depthData = photo.depthData else {
            self.depthData = nil
            return
        }
        if let orientation = photo.metadata[ String(kCGImagePropertyOrientation) ] as? UInt32 {
            depthData = depthData.applyingExifOrientation(CGImagePropertyOrientation(rawValue: orientation)!)
        }
        let depthDataImage = CIImage(cvPixelBuffer: depthData.depthDataMap, options: [.auxiliaryDepth: true])
        self.depthData = context.heifRepresentation(of: depthDataImage,
                                                    format: .RGBA8,
                                                    colorSpace: perceptualColorSpace,
                                                    options: [.portraitEffectsMatteImage: depthDataImage])
    }

    /// - Tag: DidFinishRecordingLive
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishRecordingLivePhotoMovieForEventualFileAt outputFileURL: URL, resolvedSettings: AVCaptureResolvedPhotoSettings) {
        livePhotoCaptureHandler(false)
    }

    /// - Tag: DidFinishProcessingLive
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL, duration: CMTime, photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if error != nil {
            os_log("Error processing Live Photo companion movie: \(String(describing: error))")
            return
        }
        livePhotoCompanionMovieURL = outputFileURL
    }

    /// - Tag: DidFinishCapture
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            os_log("Error capturing photo: \(String(describing: error))")
            didFinish()
            return
        }

        guard let photoData = photoData else {
            os_log("No photo data resource")
            didFinish()
            return
        }

        PHPhotoLibrary.shared().performChanges({
            let options = PHAssetResourceCreationOptions()
            let creationRequest = PHAssetCreationRequest.forAsset()
            options.uniformTypeIdentifier = self.requestedPhotoSettings.processedFileType.map { $0.rawValue }
            creationRequest.addResource(with: .photo, data: photoData, options: options)
            creationRequest.location = self.location
            if let livePhotoCompanionMovieURL = self.livePhotoCompanionMovieURL {
                let livePhotoCompanionMovieFileOptions = PHAssetResourceCreationOptions()
                livePhotoCompanionMovieFileOptions.shouldMoveFile = true
                creationRequest.addResource(with: .pairedVideo,
                                            fileURL: livePhotoCompanionMovieURL,
                                            options: livePhotoCompanionMovieFileOptions)
            }
            if let depthData = self.depthData {
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo,
                                            data: depthData,
                                            options: nil)
            }
        }, completionHandler: { _, error in
            if let error = error {
                os_log("Error occurred while saving photo to photo library: \(String(describing: error))")
            }
            self.didFinish()
        })
    }

}
