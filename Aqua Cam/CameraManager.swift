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

    func configureSession(changeCamera changeCameraDirection: Constants.Direction,
                          changeFormat changeFormatDirection: Constants.Direction,
                          doFirst: (() -> Void)? = nil
    ) {
        sessionQueue.async {
            self.session.beginConfiguration()
            doFirst?()

            // change camera
            let oldVideoDeviceInput = self.videoDeviceInput!
            var index = self.videoDevices.firstIndex(of: oldVideoDeviceInput.device) ?? 0
            index = (index + changeCameraDirection.rawValue) % self.videoDevices.count
            if index < 0 { index += self.videoDevices.count }

            let newVideoDeviceInput: AVCaptureDeviceInput
            do {
                newVideoDeviceInput = try AVCaptureDeviceInput(device: self.videoDevices[index])
            } catch {
                os_log("Error occurred while creating video device input: \(String(describing: error))")
                return
            }
            self.session.removeInput(oldVideoDeviceInput)
            if self.session.canAddInput(newVideoDeviceInput) {
                NotificationCenter.default.removeObserver(self,
                                                          name: AVCaptureDevice.subjectAreaDidChangeNotification,
                                                          object: oldVideoDeviceInput.device)
                NotificationCenter.default.addObserver(self,
                                                       selector: #selector(self.subjectAreaDidChange),
                                                       name: AVCaptureDevice.subjectAreaDidChangeNotification,
                                                       object: newVideoDeviceInput.device)
                self.session.addInput(newVideoDeviceInput)
                self.videoDeviceInput = newVideoDeviceInput
                os_log("Changed camera to: \(newVideoDeviceInput)")
            } else {
                os_log("Unable to add camera input: \(newVideoDeviceInput)")
                self.session.addInput(oldVideoDeviceInput)
            }

            // change format
            let newFormat: AVCaptureDevice.Format
            if (self.movieFileOutput != nil) {
                newFormat = self.selectFormat(direction: changeFormatDirection)
            } else {
                if self.photoOutput.isDepthDataDeliverySupported {
                    newFormat = self.videoDeviceInput.device.formats.last {
                        // a 4/3, full frame format
                        Double($0.formatDescription.dimensions.height) / Double($0.formatDescription.dimensions.width) == 0.75 &&
                        // note: not .isHighestPhotoQualitySupported
                        $0.isHighPhotoQualitySupported
                    } ?? self.videoDeviceInput.device.formats.last!
                } else {
                    newFormat = self.videoDeviceInput.device.formats.last {
                        $0.isHighestPhotoQualitySupported
                    } ?? self.videoDeviceInput.device.formats.last!
                }
            }
            do {
                try self.videoDeviceInput.device.lockForConfiguration()
                self.videoDeviceInput.device.activeFormat = newFormat
                self.videoDeviceInput.device.unlockForConfiguration()
            } catch {
                os_log("changeFormat: Could not lock device for configuration: \(String(describing: error))")
            }
            os_log("Set format to \(String(describing: self.videoDeviceInput.device.activeFormat))")

            // configure session

            if (self.movieFileOutput != nil) {
                self.videoConnection = self.movieFileOutput?.connection(with: .video)
            } else {
                self.videoConnection = self.photoOutput.connection(with: .video)
            }
            if let connection = self.videoConnection {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
//                connection.preferredVideoStabilizationMode = .off // max out photos resolution
            }

            if let maxPhotoDimensions = newFormat.supportedMaxPhotoDimensions.last {
                self.photoOutput.maxPhotoDimensions = maxPhotoDimensions
            } else {
                os_log("Error: missing max photo dimensions in photoOutput: \(String(describing: self.photoOutput))")
            }
            /*
             Set Live Photo capture and depth data delivery if it's supported. When changing cameras, the
             `livePhotoCaptureEnabled` and `depthDataDeliveryEnabled` properties of the AVCapturePhotoOutput
             get set to false when a video device is disconnected from the session. After the new video device is
             added to the session, re-enable them on the AVCapturePhotoOutput, if supported.
             */
            self.photoOutput.isLivePhotoCaptureEnabled = self.photoOutput.isLivePhotoCaptureSupported
            self.photoOutput.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliverySupported
            self.photoOutput.isPortraitEffectsMatteDeliveryEnabled = self.photoOutput.isPortraitEffectsMatteDeliverySupported
            self.photoOutput.maxPhotoQualityPrioritization = .quality

            self.session.commitConfiguration()
        }
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
        if movieFileOutput != nil {
            os_log("Switching to Photo taking")
            switchToPhoto()
            return .photo
        } else {
            os_log("Switching to Movie recording")
            switchToMovie()
            return .vga640x480 // non- .photo
        }
    }

    func switchToPhoto() {
        configureSession(changeCamera: .current, changeFormat: .current, doFirst: {
            if let movieFileOutput = self.movieFileOutput {
                self.session.removeOutput(movieFileOutput) // otherwise Live Photos are unavailable
                self.movieFileOutput = nil
            }
        })
    }

    func switchToMovie() {
        configureSession(changeCamera: .current, changeFormat: .current, doFirst: {
            let movieFileOutput = AVCaptureMovieFileOutput()
            if !self.session.canAddOutput(movieFileOutput) { return }
            self.session.addOutput(movieFileOutput)
            self.movieFileOutput = movieFileOutput
        })
    }

    func toggleMovieRecording(_ flashView: UIFlashView) {
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }
        sessionQueue.async {
            if movieFileOutput.isRecording {
                os_log("Stopping recording")
                movieFileOutput.stopRecording()
                flashView.flash(color: Colour.FLASH_REC_STOP)
            } else {
                os_log("Starting recording")
                let movieRecordingProcessor = MovieRecordingProcessor(completionHandler: { movieRecordingProcessor in
                    self.inProgressMovieRecordingDelegates[movieRecordingProcessor.uniqueID] = nil
                })
                self.inProgressMovieRecordingDelegates[movieRecordingProcessor.uniqueID] = movieRecordingProcessor
                movieRecordingProcessor.location = self.locationManager.location
                movieRecordingProcessor.startRecording(with: movieFileOutput)
                flashView.flash(color: Colour.FLASH_REC_START)
            }
        }
    }

    func capturePhoto(viewController: ViewController) {
        sessionQueue.async {
            self.photoOutput.connection(with: .video)!.videoRotationAngle = Constants.LANDSCAPE_RIGHT
            var photoSettings = AVCapturePhotoSettings()
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            if let previewPhotoPixelFormatType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewPhotoPixelFormatType]
            }
            // Live Photo capture is not supported in movie mode.
            if self.photoOutput.isLivePhotoCaptureSupported {
                let livePhotoMovieFileName = NSUUID().uuidString
                let livePhotoMovieFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((livePhotoMovieFileName as NSString).appendingPathExtension("mov")!)
                photoSettings.livePhotoMovieFileURL = URL(fileURLWithPath: livePhotoMovieFilePath)
            }
            photoSettings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            photoSettings.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliveryEnabled
            photoSettings.isPortraitEffectsMatteDeliveryEnabled = self.photoOutput.isPortraitEffectsMatteDeliveryEnabled
            photoSettings.photoQualityPrioritization = .quality
            // TODO flash
            if self.videoDeviceInput.device.isFlashAvailable {
                photoSettings.flashMode = .off
            }

            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, willCapturePhotoAnimation: {
                viewController.flashView.flash(color: Colour.FLASH_PHOTO)
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

}
