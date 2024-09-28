import AVFoundation
import os

extension CameraManager {

    func preconfigureSession(previewView: PreviewView) {
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
            self.configureSession(changeCamera: .current, changeFormat: .current) {
                // [permanent] attach audio input
                do {
                    let audioDevice = AVCaptureDevice.default(for: .audio)
                    let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)
                    guard self.session.canAddInput(audioDeviceInput) else {
                        os_log("Could not add audio device input to the session")
                        self.setupResult = .configurationFailed
                        self.session.commitConfiguration()
                        return
                    }
                    self.session.addInput(audioDeviceInput)
                } catch {
                    os_log("Could not create audio device input: \(String(describing: error))")
                    // Audio is optional - continue
                }

                // [permanent] add photo output
                guard self.session.canAddOutput(self.photoOutput) else {
                    os_log("Could not add photo output to the session")
                    self.setupResult = .configurationFailed
                    self.session.commitConfiguration()
                    return
                }
                self.session.addOutput(self.photoOutput)
            }
            // do last
            self.sessionQueue.async {
                DispatchQueue.main.async {
                    previewView.videoPreviewLayer.connection!.videoRotationAngle = Constants.LANDSCAPE_RIGHT
                }
            }
        }
    }

    func startSession(completionHandler: (() -> Void)? = nil) {
        os_log("Starting the session")
        sessionQueue.async {
            if self.keyValueObservations.isEmpty {
                self.addObservers()
            }
            self.session.startRunning()
            if self.session.isRunning {
                Logger.log(.event, "camera-awake")
            } else {
                os_log("Unable to start session")
            }
            DispatchQueue.main.async {
                completionHandler?()
                os_log("Wakeup from sleep finished")
            }
        }
    }

    func shutdownSession() {
        sessionQueue.async {
            if self.setupResult == .success {
                os_log("Shutting down the session")
                self.session.stopRunning()
                Logger.log(.event, "camera-asleep")
                self.removeObservers()
            }
        }
    }

    func addObservers() {
        NotificationCenter.default.addObserver(self,
                                      selector:#selector(subjectAreaDidChange),
                                          name:AVCaptureDevice.subjectAreaDidChangeNotification,
                                        object:videoDeviceInput.device)

        NotificationCenter.default.addObserver(self,
                                      selector:#selector(sessionRuntimeError),
                                          name:AVCaptureSession.runtimeErrorNotification,
                                        object:session)

        NotificationCenter.default.addObserver(self,
                                      selector:#selector(sessionWasInterrupted),
                                          name:AVCaptureSession.wasInterruptedNotification,
                                        object:session)

        NotificationCenter.default.addObserver(self,
                                      selector:#selector(sessionInterruptionEnded),
                                          name:AVCaptureSession.interruptionEndedNotification,
                                        object:session)
    }

    func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        keyValueObservations.forEach { $0.invalidate() }
        keyValueObservations.removeAll()
    }

    @objc
    func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        os_log("Capture session runtime error: \(String(describing: error))")
        Logger.log(.error, "capture-session: \(String(describing: error))")
    }

    @objc
    func sessionWasInterrupted(notification: NSNotification) {
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            os_log("Capture session was interrupted with reason \(String(describing: reason))")
            Logger.log(.event, "capture-session: interrupted: \(String(describing: reason))")
            if reason == .videoDeviceNotAvailableDueToSystemPressure {
                os_log("Session stopped running due to shutdown system pressure level.")
            }
        }
    }

    @objc
    func sessionInterruptionEnded(notification: NSNotification) {
        os_log("Capture session interruption ended")
        Logger.log(.event, "capture-session: interruption ended")
    }

    @objc
    func subjectAreaDidChange(notification: NSNotification) {
        focusAndExposure(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure)
    }

}
