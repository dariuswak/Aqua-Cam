import AVFoundation
import CoreLocation
import UIKit
import os

class CameraManager {

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

    let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera],
        mediaType: .video, position: .back)

    var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()

    var inProgressMovieRecordingDelegates = [NSUUID: MovieRecordingProcessor]()

    var inProgressLivePhotoCapturesCount = 0

    var setupResult: SessionSetupResult = .success

    var keyValueObservations = [NSKeyValueObservation]()

    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!

    var movieFileOutput: AVCaptureMovieFileOutput?

    func launchConfigureSession(previewView: PreviewView) {
        sessionQueue.async {
            self.configureSession(previewView: previewView)
        }
    }

    func configureSession(previewView: PreviewView) {
        if setupResult != .success {
            return
        }

        session.beginConfiguration()

        session.sessionPreset = .photo

        // Add video input.
        do {
            guard let videoDevice = videoDeviceDiscoverySession.devices.first else {
                os_log("No back-located video devices unavailable.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
//            let videoDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)!
//            let videoDevice = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back)!
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)

            guard session.canAddInput(videoDeviceInput) else {
                os_log("Couldn't add video device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            session.addInput(videoDeviceInput)
            self.videoDeviceInput = videoDeviceInput

            DispatchQueue.main.async {
                previewView.videoPreviewLayer.connection?.videoOrientation = Constants.LANDSCAPE_RIGHT
            }
        } catch {
            os_log("Couldn't create video device input: \(String(describing: error))")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
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

        session.commitConfiguration()
    }

    /// - Tag: ChangeCamera
    func changeCamera() {
        let oldVideoDeviceInput = videoDeviceInput!

        var index = videoDeviceDiscoverySession.devices.firstIndex(of: oldVideoDeviceInput.device)!
        index = (index + 1) % videoDeviceDiscoverySession.devices.count
        let newVideoDeviceInput: AVCaptureDeviceInput
        do {
            newVideoDeviceInput = try AVCaptureDeviceInput(device: videoDeviceDiscoverySession.devices[index])
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
            session.sessionPreset = Constants.HD_4K

            let tenBitsHdrFormat = videoDeviceInput.device.formats.last { format in CMFormatDescriptionGetMediaSubType(format.formatDescription) == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange }
            if tenBitsHdrFormat != nil {
                print("Setting 'x420' format \(String(describing: tenBitsHdrFormat))")
                do {
                    try videoDeviceInput.device.lockForConfiguration()
                    videoDeviceInput.device.activeFormat = tenBitsHdrFormat!
                    videoDeviceInput.device.unlockForConfiguration()
                } catch {
                    os_log("changeCamera_1: Could not lock device for configuration: \(String(describing: error))")
                }
            } else {
                let highestQualityFormat = videoDeviceInput.device.formats.last
                do {
                    try videoDeviceInput.device.lockForConfiguration()
                    videoDeviceInput.device.activeFormat = highestQualityFormat!
                    videoDeviceInput.device.unlockForConfiguration()
                } catch {
                    os_log("changeCamera_2: Could not lock device for configuration: \(String(describing: error))")
                }
            }
            os_log("Set video format \(String(describing: self.videoDeviceInput.device.activeFormat))")
            if let connection = movieFileOutput?.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
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

        session.commitConfiguration()
    }

    func cycleLockFocusAndExposureInCentre(viewController: ViewController) {
        if (self.videoDeviceInput.device.focusMode == .continuousAutoFocus) {
            UIView.animate(withDuration: 1,
                           animations: { viewController.focusIndicator.alpha = 1 },
                           completion: { _ in
                               UIView.animate(withDuration: 1,
                                              animations: { viewController.focusIndicator.alpha = 0 })
                           })
            focusAndExposure(with: .locked, exposureMode: .autoExpose)
        } else {
            focusAndExposure(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure)
        }
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

    func cyclePhotoAndVideo() {
        if session.sessionPreset == .photo {
            os_log("Switching to Movie recording")
            sessionQueue.async {
                self.switchToMovie()
            }
        } else {
            os_log("Switching to Photo taking")
            sessionQueue.async {
                self.switchToPhoto()
            }
        }
    }

    func switchToPhoto() {
        session.beginConfiguration()
        session.removeOutput(movieFileOutput!) // otherwise Live Photos are unavailable
        movieFileOutput = nil
        session.sessionPreset = .photo
        photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
        photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
        photoOutput.isPortraitEffectsMatteDeliveryEnabled = photoOutput.isPortraitEffectsMatteDeliverySupported
        photoOutput.maxPhotoQualityPrioritization = .quality
        session.commitConfiguration()
    }

    func switchToMovie() {
        let movieFileOutput = AVCaptureMovieFileOutput()
        if !session.canAddOutput(movieFileOutput) { return }
        session.beginConfiguration()
        session.addOutput(movieFileOutput)
        session.sessionPreset = Constants.HD_4K

        let tenBitsHdrFormat = videoDeviceInput.device.formats.last { format in CMFormatDescriptionGetMediaSubType(format.formatDescription) == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange }
        if tenBitsHdrFormat != nil {
            print("Setting 'x420' format \(String(describing: tenBitsHdrFormat))")
            do {
                try videoDeviceInput.device.lockForConfiguration()
                videoDeviceInput.device.activeFormat = tenBitsHdrFormat!
                videoDeviceInput.device.unlockForConfiguration()
            } catch {
                os_log("switchToMovie_1: Could not lock device for configuration: \(String(describing: error))")
            }
        } else {
            let highestQualityFormat = videoDeviceInput.device.formats.last
            do {
                try videoDeviceInput.device.lockForConfiguration()
                videoDeviceInput.device.activeFormat = highestQualityFormat!
                videoDeviceInput.device.unlockForConfiguration()
            } catch {
                os_log("switchToMovie_2: Could not lock device for configuration: \(String(describing: error))")
            }
        }
        os_log("Set video format \(String(describing: self.videoDeviceInput.device.activeFormat))")
        if let connection = movieFileOutput.connection(with: .video) {
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }
        session.commitConfiguration()
        self.movieFileOutput = movieFileOutput
    }

    // MARK: Recording Movies

    func toggleMovieRecording() {
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }
        sessionQueue.async {
            if movieFileOutput.isRecording {
                os_log("Stopping recording")
                movieFileOutput.stopRecording()
            } else {
                os_log("Starting recording")
                let movieRecordingProcessor = MovieRecordingProcessor { movieRecordingProcessor in
                    self.sessionQueue.async {
                        self.inProgressMovieRecordingDelegates[movieRecordingProcessor.uniqueID] = nil
                    }
                }
                self.inProgressMovieRecordingDelegates[movieRecordingProcessor.uniqueID] = movieRecordingProcessor
                movieRecordingProcessor.location = self.locationManager.location
                movieRecordingProcessor.startRecording(with: movieFileOutput)
            }
        }
    }

    // MARK: Photos

    func capturePhoto(previewView: PreviewView, viewController: ViewController) {
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
            photoSettings.isHighResolutionPhotoEnabled = true
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
                DispatchQueue.main.async {
                    previewView.videoPreviewLayer.backgroundColor = UIColor.white.cgColor
                    UIView.animate(withDuration: 0.35) {
                        previewView.videoPreviewLayer.backgroundColor = UIColor.black.cgColor
                    }
                }
            }, livePhotoCaptureHandler: { capturing in
                self.sessionQueue.async {
                    if capturing {
                        self.inProgressLivePhotoCapturesCount += 1
                    } else if self.inProgressLivePhotoCapturesCount > 0 {
                        self.inProgressLivePhotoCapturesCount -= 1
                    }

                    let inProgressLivePhotoCapturesCount = self.inProgressLivePhotoCapturesCount
                    DispatchQueue.main.async {
                        if inProgressLivePhotoCapturesCount > 0 {
                            viewController.capturingLivePhotoIndicator.isHidden = false
                        } else {
                            viewController.capturingLivePhotoIndicator.isHidden = true
                        }
                    }
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
