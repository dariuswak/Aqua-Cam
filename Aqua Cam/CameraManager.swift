import AVFoundation
import CoreLocation
import UIKit
import os

class CameraManager: NSObject {

    enum SessionSetupResult {
        case success
        case notAuthorizedCamera
        case notAuthorizedAlbum
        case configurationFailed
    }

    let locationManager = CLLocationManager()

    let session = AVCaptureSession()

    let sessionQueue = DispatchQueue(label: "session queue")

    let photoOutput = AVCapturePhotoOutput()

    let videoDevices = AVCaptureDevice.DiscoverySession(
        deviceTypes: Constants.CAMERAS, mediaType: .video, position: .back
    ).devices

    var currentVideoFormat: FormatType = .UHD

    var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()

    var inProgressMovieRecordingDelegates = [NSUUID: MovieRecordingProcessor]()

    var inProgressLivePhotoCapturesCount = 0

    var setupResult: SessionSetupResult = .success

    var keyValueObservations = [NSKeyValueObservation]()

    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!

    @objc dynamic var movieFileOutput: AVCaptureMovieFileOutput?

    @objc dynamic var videoConnection: AVCaptureConnection?

    func launchConfigureSession(previewView: PreviewView) {
        if setupResult != .success {
            return
        }
        guard let videoDevice = videoDevices.first else {
            os_log("No back-located video devices unavailable.")
            setupResult = .configurationFailed
            return
        }
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            os_log("Couldn't create video device input: \(String(describing: error))")
            setupResult = .configurationFailed
            return
        }
        sessionQueue.async {
            self.configureSession(previewView: previewView)
        }
    }

    func configureSession(previewView: PreviewView) {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Add video input.
        guard session.canAddInput(videoDeviceInput) else {
            os_log("Couldn't add video device input to the session.")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        session.addInput(videoDeviceInput)
        DispatchQueue.main.async {
            previewView.videoPreviewLayer.connection?.videoOrientation = Constants.LANDSCAPE_RIGHT
        }

        // Add an audio input device.
        do {
            let audioDevice = AVCaptureDevice.default(for: .audio)
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)

            guard session.canAddInput(audioDeviceInput) else {
                os_log("Could not add audio device input to the session")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            session.addInput(audioDeviceInput)
        } catch {
            os_log("Could not create audio device input: \(String(describing: error))")
        }

        guard session.canAddOutput(photoOutput) else {
            os_log("Could not add photo output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        session.addOutput(photoOutput)

        photoOutput.isHighResolutionCaptureEnabled = true
        photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
        photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
        photoOutput.isPortraitEffectsMatteDeliveryEnabled = photoOutput.isPortraitEffectsMatteDeliverySupported
        photoOutput.maxPhotoQualityPrioritization = .quality
        videoConnection = photoOutput.connection(with: .video)
        if let connection = videoConnection {
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }

        session.commitConfiguration()
    }

    /// - Tag: ChangeCamera
    func changeCamera(direction: Constants.Direction) {
        let oldVideoDeviceInput = videoDeviceInput!

        var index = videoDevices.firstIndex(of: oldVideoDeviceInput.device)!
        index = (index + direction.rawValue) % videoDevices.count
        if index < 0 { index += videoDevices.count }

        let newVideoDeviceInput: AVCaptureDeviceInput
        do {
            newVideoDeviceInput = try AVCaptureDeviceInput(device: videoDevices[index])
        } catch {
            os_log("Error occurred while creating video device input: \(String(describing: error))")
            return
        }

        session.beginConfiguration()

        session.removeInput(oldVideoDeviceInput)
        if session.canAddInput(newVideoDeviceInput) {
            NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: oldVideoDeviceInput.device)
            NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: newVideoDeviceInput.device)
            session.addInput(newVideoDeviceInput)
            videoDeviceInput = newVideoDeviceInput
            os_log("Changed camera to: \(newVideoDeviceInput)")
        } else {
            os_log("Unable to add camera input: \(newVideoDeviceInput)")
            session.addInput(oldVideoDeviceInput)
        }

        if (movieFileOutput != nil) {
            let currentFormat = selectFormat(direction: Constants.Direction.current)
            do {
                try videoDeviceInput.device.lockForConfiguration()
                videoDeviceInput.device.activeFormat = currentFormat
                videoDeviceInput.device.unlockForConfiguration()
            } catch {
                os_log("changeCamera_1: Could not lock device for configuration: \(String(describing: error))")
            }
            os_log("Set video format \(String(describing: self.videoDeviceInput.device.activeFormat))")
            videoConnection = movieFileOutput?.connection(with: .video)
        } else {
            if photoOutput.isDepthDataDeliverySupported {
                do {
                    try videoDeviceInput.device.lockForConfiguration()
                    videoDeviceInput.device.activeFormat = videoDeviceInput.device.formats.last { $0.isHighPhotoQualitySupported == true // note: not .isHighestPhotoQualitySupported
                    }!
                    videoDeviceInput.device.unlockForConfiguration()
                } catch {
                    os_log("changeCamera_2: Could not lock device for configuration: \(String(describing: error))")
                }
            } else {
                session.sessionPreset = .photo
            }
            videoConnection = photoOutput.connection(with: .video)
        }

        /*
         Set Live Photo capture and depth data delivery if it's supported. When changing cameras, the
         `livePhotoCaptureEnabled` and `depthDataDeliveryEnabled` properties of the AVCapturePhotoOutput
         get set to false when a video device is disconnected from the session. After the new video device is
         added to the session, re-enable them on the AVCapturePhotoOutput, if supported.
         */
        photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
        photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
        photoOutput.isPortraitEffectsMatteDeliveryEnabled = photoOutput.isPortraitEffectsMatteDeliverySupported
        photoOutput.maxPhotoQualityPrioritization = .quality
        if let connection = videoConnection {
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }

        photoOutput.isHighResolutionCaptureEnabled = !photoOutput.isDepthDataDeliveryEnabled
        session.commitConfiguration()
    }

    func changeFormat(direction: Constants.Direction) {
        guard movieFileOutput != nil else { return }
        session.beginConfiguration()
        let newFormat = selectFormat(direction: direction)
        do {
            try videoDeviceInput.device.lockForConfiguration()
            videoDeviceInput.device.activeFormat = newFormat
            videoDeviceInput.device.unlockForConfiguration()
        } catch {
            os_log("changeFormat: Could not lock device for configuration: \(String(describing: error))")
        }
        os_log("Set video format \(String(describing: self.videoDeviceInput.device.activeFormat))")
        videoConnection = movieFileOutput?.connection(with: .video)
        if let connection = videoConnection {
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }
        photoOutput.isHighResolutionCaptureEnabled = !photoOutput.isDepthDataDeliveryEnabled
        session.commitConfiguration()
    }

    func selectFormat(direction: Constants.Direction) -> AVCaptureDevice.Format {
        var index = currentVideoFormat.rawValue
        index = (index + direction.rawValue) % FormatType.allCases.count
        if index < 0 { index += FormatType.allCases.count }
        currentVideoFormat = FormatType.init(rawValue: index)!
        let selectedFormatDescription = FormatDescription.of(currentVideoFormat)
        //videoDeviceInput.device.formats.forEach { os_log("FORMAT: \($0)") }
        return videoDeviceInput.device.formats.last {
            $0.formatDescription.dimensions.width == selectedFormatDescription.dimensions.width &&
            $0.formatDescription.dimensions.height == selectedFormatDescription.dimensions.height &&
            $0.videoSupportedFrameRateRanges.last!.maxFrameRate == selectedFormatDescription.frameRate &&
            !($0.isVideoBinned) && // binned formats are after the best!
            !($0.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange) // x422 only supports ProRes
        } ?? selectFormat(direction: (direction == .current ? .previous : direction))
    }

    func lockFocusAndExposureInCentre() {
        focusAndExposure(with: .autoFocus, exposureMode: .autoExpose)
    }

    func focusAndExposure(with focusMode: AVCaptureDevice.FocusMode,
                          exposureMode: AVCaptureDevice.ExposureMode) {
        let centre = CGPoint(x: 0.5, y: 0.5)

        os_log("Focus: \(String(describing: focusMode)), exposure: \(String(describing: exposureMode))")
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = centre
                    device.focusMode = focusMode
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = centre
                    device.exposureMode = exposureMode
                }
                device.isSubjectAreaChangeMonitoringEnabled = true
                device.unlockForConfiguration()
            } catch {
                os_log("focusAndExposure: Could not lock device for configuration: \(String(describing: error))")
            }
        }
    }

    func cyclePhotoAndVideo() -> AVCaptureSession.Preset {
        if movieFileOutput == nil {
            os_log("Switching to Movie recording")
            sessionQueue.async {
                self.switchToMovie()
            }
            return .vga640x480 // non- .photo
        } else {
            os_log("Switching to Photo taking")
            sessionQueue.async {
                self.switchToPhoto()
            }
            return .photo
        }
    }

    func switchToPhoto() {
        session.beginConfiguration()
        if let movieFileOutput = movieFileOutput {
            session.removeOutput(movieFileOutput) // otherwise Live Photos are unavailable
        }
        movieFileOutput = nil
        session.sessionPreset = .photo
        photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
        photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
        photoOutput.isPortraitEffectsMatteDeliveryEnabled = photoOutput.isPortraitEffectsMatteDeliverySupported
        photoOutput.maxPhotoQualityPrioritization = .quality
        videoConnection = photoOutput.connection(with: .video)
        if let connection = videoConnection {
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }
        photoOutput.isHighResolutionCaptureEnabled = !photoOutput.isDepthDataDeliveryEnabled
        session.commitConfiguration()
    }

    func switchToMovie() {
        let movieFileOutput = AVCaptureMovieFileOutput()
        if !session.canAddOutput(movieFileOutput) { return }
        session.beginConfiguration()
        session.addOutput(movieFileOutput)

        let currentFormat = selectFormat(direction: Constants.Direction.current)
        do {
            try videoDeviceInput.device.lockForConfiguration()
            videoDeviceInput.device.activeFormat = currentFormat
            videoDeviceInput.device.unlockForConfiguration()
        } catch {
            os_log("changeCamera: Could not lock device for configuration: \(String(describing: error))")
        }
        os_log("Set video format \(String(describing: self.videoDeviceInput.device.activeFormat))")
        videoConnection = movieFileOutput.connection(with: .video)
        if let connection = videoConnection {
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }
        photoOutput.isHighResolutionCaptureEnabled = !photoOutput.isDepthDataDeliveryEnabled
        session.commitConfiguration()
        self.movieFileOutput = movieFileOutput
    }

    // MARK: Recording Movies

    func toggleMovieRecording(_ flashView: UIFlashView) {
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }
        sessionQueue.async {
            if movieFileOutput.isRecording {
                os_log("Stopping recording")
                flashView.flash(color: UIColor.black)
                movieFileOutput.stopRecording()
            } else {
                os_log("Starting recording")
                flashView.flash(color: UIColor.systemRed)
                let movieRecordingProcessor = MovieRecordingProcessor(completionHandler: { movieRecordingProcessor in
                    self.inProgressMovieRecordingDelegates[movieRecordingProcessor.uniqueID] = nil
                })
                self.inProgressMovieRecordingDelegates[movieRecordingProcessor.uniqueID] = movieRecordingProcessor
                movieRecordingProcessor.location = self.locationManager.location
                movieRecordingProcessor.startRecording(with: movieFileOutput)
            }
        }
    }

    // MARK: Photos

    func capturePhoto(viewController: ViewController) {
        sessionQueue.async {
            self.photoOutput.connection(with: .video)!.videoOrientation = Constants.LANDSCAPE_RIGHT
            var photoSettings = AVCapturePhotoSettings()
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            // TODO flash
            if self.videoDeviceInput.device.isFlashAvailable {
                photoSettings.flashMode = .off
            }
            photoSettings.isHighResolutionPhotoEnabled = self.photoOutput.isHighResolutionCaptureEnabled
            if let previewPhotoPixelFormatType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewPhotoPixelFormatType]
            }
            // Live Photo capture is not supported in movie mode.
            if self.photoOutput.isLivePhotoCaptureSupported {
                let livePhotoMovieFileName = NSUUID().uuidString
                let livePhotoMovieFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((livePhotoMovieFileName as NSString).appendingPathExtension("mov")!)
                photoSettings.livePhotoMovieFileURL = URL(fileURLWithPath: livePhotoMovieFilePath)
            }
            photoSettings.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliveryEnabled
            photoSettings.isPortraitEffectsMatteDeliveryEnabled = self.photoOutput.isPortraitEffectsMatteDeliveryEnabled
            photoSettings.photoQualityPrioritization = .quality

            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, willCapturePhotoAnimation: {
                viewController.flashView.flash(color: UIColor.systemGray)
            }, livePhotoCaptureHandler: { capturing in
                self.sessionQueue.async {
                    if capturing {
                        self.inProgressLivePhotoCapturesCount += 1
                    } else if self.inProgressLivePhotoCapturesCount > 0 {
                        self.inProgressLivePhotoCapturesCount -= 1
                    }
                    viewController.capturingLivePhotoIndicator.show(if: self.inProgressLivePhotoCapturesCount > 0)
                }
            }, completionHandler: { photoCaptureProcessor in
                // When the capture is complete, remove a reference to the photo capture delegate so it can be deallocated.
                self.sessionQueue.async {
                    self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.uniqueID] = nil
                }
            }, photoProcessingHandler: { animate in
                DispatchQueue.main.async {
                    if animate {
                        viewController.processingIndicator.startAnimating()
                    } else {
                        viewController.processingIndicator.stopAnimating()
                    }
                }
            })

            photoCaptureProcessor.location = self.locationManager.location

            // The photo output holds a weak reference to the photo capture delegate and stores it in an array to maintain a strong reference.
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.uniqueID] = photoCaptureProcessor
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)
        }
    }

    // MARK: Session lifecycle

    @objc
    func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        if error.code == AVError.Code.unknown
                && error.userInfo[NSLocalizedFailureReasonErrorKey] as! String == "An unknown error occurred (-16401)"
                && error.userInfo[NSLocalizedDescriptionKey] as! String == "The operation could not be completed"
                && (error.userInfo[NSUnderlyingErrorKey] as! NSError).domain == NSOSStatusErrorDomain {
            return
        }
        os_log("Capture session runtime error: \(String(describing: error))")
    }

    @objc
    func sessionWasInterrupted(notification: NSNotification) {
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            os_log("Capture session was interrupted with reason \(String(describing: reason).lowercased())")
            if reason == .videoDeviceNotAvailableDueToSystemPressure {
                os_log("Session stopped running due to shutdown system pressure level.")
            }
        }
    }

    @objc
    func sessionInterruptionEnded(notification: NSNotification) {
        os_log("Capture session interruption ended")
    }

    // MARK: Notifications

    func addObservers() {
// TODO
//        let systemPressureStateObservation = observe(\.videoDeviceInput.device.systemPressureState, options: .new) { _, change in
//            guard let systemPressureState = change.newValue else { return }
//            self.setRecommendedFrameRateRangeForPressureState(systemPressureState: systemPressureState)
//        }
//        keyValueObservations.append(systemPressureStateObservation)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(subjectAreaDidChange),
                                               name: .AVCaptureDeviceSubjectAreaDidChange,
                                               object: videoDeviceInput.device)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionRuntimeError),
                                               name: .AVCaptureSessionRuntimeError,
                                               object: session)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionWasInterrupted),
                                               name: .AVCaptureSessionWasInterrupted,
                                               object: session)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionInterruptionEnded),
                                               name: .AVCaptureSessionInterruptionEnded,
                                               object: session)
    }

    func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        keyValueObservations.forEach { $0.invalidate() }
        keyValueObservations.removeAll()
    }

    @objc
    func subjectAreaDidChange(notification: NSNotification) {
        focusAndExposure(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure)
    }

}
