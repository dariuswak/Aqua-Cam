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
                self.photoOutput.isHighResolutionCaptureEnabled = true
            }
            // do last
            self.sessionQueue.async {
                DispatchQueue.main.async {
                    previewView.videoPreviewLayer.connection!.videoOrientation = Constants.LANDSCAPE_RIGHT
                }
            }
        }
    }

    func startSession() {
        os_log("Starting the session")
        sessionQueue.async {
            if self.keyValueObservations.isEmpty {
                self.addObservers()
            }
            self.session.startRunning()
            if !self.session.isRunning {
                os_log("Unable to start session")
            }
        }
    }

    func shutdownSession() {
        sessionQueue.async {
            if self.setupResult == .success {
                os_log("Shutting down the session")
                self.session.stopRunning()
                self.removeObservers()
            }
        }
    }

    func sleepSession() {
        os_log("Entering sleep")
        sessionQueue.async {
            self.videoDeviceInput.ports
                .filter { port in port.mediaType == AVMediaType.video }
                .forEach { port in
                    os_log("Disabling video port: \(port)")
                    port.isEnabled = false
                }
            os_log("Entered sleep")
        }
    }

    func wakeUpSession(completionHandler: @escaping () -> Void) {
        os_log("Waking up from sleep")
        sessionQueue.async {
            self.videoDeviceInput.ports
                .filter { port in port.mediaType == AVMediaType.video }
                .forEach { port in
                    os_log("Enabling video port: \(port)")
                    port.isEnabled = true
                }
            DispatchQueue.main.async {
                completionHandler()
                os_log("Wakeup from sleep finished")
            }
        }
    }

    func addObservers() {
        keyValueObservations.append(observe(\.videoDeviceInput.device.systemPressureState) { _,_ in
            os_log("System pressure state changed to: \(self.videoDeviceInput.device.systemPressureState)")
        })

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

    @objc
    func subjectAreaDidChange(notification: NSNotification) {
        focusAndExposure(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure)
    }

}
