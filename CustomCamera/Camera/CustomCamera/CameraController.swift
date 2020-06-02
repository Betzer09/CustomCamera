//
//  CameraController.swift
//  CustomCamera
//
//  Created by Austin Betzer on 5/29/20.
//  Copyright © 2020 Austin Betzer. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

/**
This view will render and handle capturing both photos and vidoes
*/
class CameraController: NSObject {
    
    // MARK: - Public Properties
    /// The current camera position set
    private(set) var currentCameraPosition: CameraPosition?
    private(set) var photoCaptureCompletionBlock: ((UIImage?, Error?) -> Void)?
    /// The current zoom scale
    private(set) var pinchScale: CGFloat = 1.0
    /// The current capture session
    private(set) var captureSession: AVCaptureSession?
    /// Movie File Output variable
    private(set) var movieFileOutput: AVCaptureMovieFileOutput?
    /// Returns true if video is currently being recorded
    private(set) public var isVideoRecording = false
    private(set) var videoQuality : AVCaptureSession.Preset = .high
    /// The maximum duration for a video, in seconds
    private(set) var maximumVideoDuration: Double = 15.0
    

    
    // MARK: - Private Properties
    private var frontCameraInput: AVCaptureDeviceInput?
    private lazy var frontCamera: AVCaptureDevice? = {
       return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    }()
    
    
    private var rearCameraInput: AVCaptureDeviceInput?
    private lazy var rearCamera: AVCaptureDevice? = {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }()
    
    /// The current output device
    private var currentOutputDevcie: AVCaptureDevice? {
        get {
            let output: AVCaptureDevice? = currentCameraPosition == .front ? frontCamera : rearCamera
            guard let device = output else {return nil}
            return device
        }
    }
    
    /// The device used to capture audio
    let audioDevice = AVCaptureDevice.default(for: .audio)
    
    private var photoOutput: AVCapturePhotoOutput?
    
    /**
     The video preview layer, this layer is added as a sublayer to the view controller so you can see the current frame of the camera. Meaning this just plays back what the you are capturing.
     */
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    /// Indicates the mode that flash is currently in
    private var flashMode = AVCaptureDevice.FlashMode.off
    
    // MARK: - Video Properties
    /// Serial queue used for setting up session
    fileprivate let sessionQueue = DispatchQueue(label: "session queue", attributes: [])
    /// BackgroundID variable for video recording
    fileprivate var backgroundRecordingID: UIBackgroundTaskIdentifier? = nil
    
    /// Video will be recorded to this folder
    private var outputFolder: String = NSTemporaryDirectory()
    
    /// Sets output video codec
    public var videoCodecType: AVVideoCodecType? = nil
    
    /// The camera delegate that informts you have videos actions
    public weak var cameraDelegate: CameraControllerDelegate?
}

extension CameraController {
    // MARK: - Public Methods
    /**
     Stops running the current capture session, meaing the user will stop getting a preview of their camera position
     */
    public func stopCurrentSession() {
        self.captureSession?.stopRunning()
        self.previewLayer?.isHidden = true
    }

    /**
     Starts running the current capture session, meaing the user will get a preview of their camera position
     */
    public func startRunningSession() {
        self.captureSession?.startRunning()
        self.previewLayer?.isHidden = false
    }
    
    /**
     Toggles the captures session flash abilites
     */
    public func toggleFlash(completion: @escaping(_ isFlashOn: Bool) ->()) {
        switch flashMode {
        case .auto, .off:
            flashMode = .on
            completion(true)
        case .on:
            flashMode = .off
            completion(false)
        @unknown default:
            print("[CameraController]: Unknown flash state: \(flashMode)")
            completion(false)
        }
    }
    
    /**
     pass in a pintch gesture and the capture device will zoom
     */
    public func zoom(pintch gesture: UIPinchGestureRecognizer) {
        guard let device = currentOutputDevcie else {return}
        
        do {
            try device.lockForConfiguration()
            switch gesture.state {
            case .began:
                self.pinchScale = device.videoZoomFactor
            case .changed:
                var factor = self.pinchScale * gesture.scale
                factor = max(1, min(factor, device.activeFormat.videoMaxZoomFactor))
                device.videoZoomFactor = factor
            default:
                break
            }
            device.unlockForConfiguration()
        } catch {
            // handle exception
            print("[CameraController] failed to zoom: \(error.localizedDescription)")
        }
    }
    
    
    public func prepare(withVideoQuality: AVCaptureSession.Preset = .high, completionHandler: @escaping (Error?) -> Void) {
        func createCaptureSession() {
            self.captureSession = AVCaptureSession()
        }
        
        func configureCaptureDevices() throws {
            
            let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera], mediaType: AVMediaType.video, position: .unspecified)
            
            let cameras = session.devices.compactMap { $0 }
            guard !cameras.isEmpty else { throw CameraControllerError.noCamerasAvailable }
            
            
            try? rearCamera?.lockForConfiguration()
            rearCamera?.focusMode = .continuousAutoFocus
            rearCamera?.unlockForConfiguration()
            
        }
        
        func configureDeviceInputs() throws {
            guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing }
            
            if let rearCamera = self.rearCamera {
                self.rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)
                
                if captureSession.canAddInput(self.rearCameraInput!) { captureSession.addInput(self.rearCameraInput!) }
                self.currentCameraPosition = .rear
                
            } else if let frontCamera = self.frontCamera {
                self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
                
                if captureSession.canAddInput(self.frontCameraInput!) { captureSession.addInput(self.frontCameraInput!) }
                else { throw CameraControllerError.inputsAreInvalid }
                
                
                self.currentCameraPosition = .front
            } else { throw CameraControllerError.noCamerasAvailable }
            
            let audioInput = try AVCaptureDeviceInput(device: self.audioDevice!)
            if captureSession.canAddInput(audioInput) {captureSession.addInput(audioInput)}
        }
        
        func configurePhotoOutput() throws {
            guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing }
            
            self.photoOutput = AVCapturePhotoOutput()
            self.photoOutput!.setPreparedPhotoSettingsArray([AVCapturePhotoSettings(format: [AVVideoCodecKey : AVVideoCodecType.jpeg])], completionHandler: nil)
            
            if captureSession.canAddOutput(self.photoOutput!) { captureSession.addOutput(self.photoOutput!) }
            captureSession.startRunning()
        }
        
        func configureVideoOutput() throws {
            let movieFileOutput = AVCaptureMovieFileOutput()
            movieFileOutput.maxRecordedDuration = CMTime(seconds: maximumVideoDuration, preferredTimescale: 1)
            

            if self.captureSession?.canAddOutput(movieFileOutput) ?? false {
                self.captureSession?.addOutput(movieFileOutput)
                if let connection = movieFileOutput.connection(with: AVMediaType.video) {
                    if connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = .auto
                    }

                    if #available(iOS 11.0, *) {
                        if let videoCodecType = videoCodecType {
                            if movieFileOutput.availableVideoCodecTypes.contains(videoCodecType) == true {
                                // Use the H.264 codec to encode the video.
                                movieFileOutput.setOutputSettings([AVVideoCodecKey: videoCodecType], for: connection)
                            }
                        }
                    }
                }
                self.movieFileOutput = movieFileOutput
            }
        }
        
        
        /**
         Front facing camera will always be set to VideoQuality.high
         
         If set video quality is not supported, videoQuality variable will be set to VideoQuality.high
         Configure image quality preset
         */
        func configureVideoPreset() {
            if currentCameraPosition == .front {
                captureSession?.sessionPreset = .high
            } else {
                if captureSession?.canSetSessionPreset(.high) ?? false {
                    captureSession?.sessionPreset = videoQuality
                } else {
                    captureSession?.sessionPreset = .high
                }
            }
        }
        
        DispatchQueue(label: "prepare").async {
            do {
                createCaptureSession()
                configureVideoPreset()
                try configureCaptureDevices()
                try configureDeviceInputs()
                try configurePhotoOutput()
                try configureVideoOutput()
            }
                
            catch {
                DispatchQueue.main.async {
                    completionHandler(error)
                }
                
                return
            }
            
            DispatchQueue.main.async {
                completionHandler(nil)
            }
        }
    }
    
    func displayPreview(on view: UIView) throws {
        guard let captureSession = self.captureSession, captureSession.isRunning else { throw CameraControllerError.captureSessionIsMissing }
        
        self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
        self.previewLayer?.connection?.videoOrientation = .portrait
        
        view.layer.insertSublayer(self.previewLayer!, at: 0)
        self.previewLayer?.frame = view.frame
    }
    
    func switchCameras() throws {
        guard let currentCameraPosition = currentCameraPosition, let captureSession = self.captureSession, captureSession.isRunning else { throw CameraControllerError.captureSessionIsMissing }
        
        captureSession.beginConfiguration()
        
        func switchToFrontCamera() throws {
            
            guard let rearCameraInput = self.rearCameraInput, captureSession.inputs.contains(rearCameraInput),
                let frontCamera = self.frontCamera else { throw CameraControllerError.invalidOperation }
            
            self.frontCameraInput = try AVCaptureDeviceInput(device: frontCamera)
            
            captureSession.removeInput(rearCameraInput)
            
            if captureSession.canAddInput(self.frontCameraInput!) {
                captureSession.addInput(self.frontCameraInput!)
                
                self.currentCameraPosition = .front
            } else {
                throw CameraControllerError.invalidOperation
            }
        }
        
        func switchToRearCamera() throws {
            
            guard let frontCameraInput = self.frontCameraInput, captureSession.inputs.contains(frontCameraInput),
                let rearCamera = self.rearCamera else { throw CameraControllerError.invalidOperation }
            
            self.rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)
            
            captureSession.removeInput(frontCameraInput)
            
            if captureSession.canAddInput(self.rearCameraInput!) {
                captureSession.addInput(self.rearCameraInput!)
                
                self.currentCameraPosition = .rear
            }
                
            else { throw CameraControllerError.invalidOperation }
        }
        
        switch currentCameraPosition {
        case .front:
            try switchToRearCamera()
            
        case .rear:
            try switchToFrontCamera()
        }
        
        captureSession.commitConfiguration()
    }
    
    /**
     Captures the current image in the preview
     */
    public func captureImage(completion: @escaping (UIImage?, Error?) -> Void) {
        guard let captureSession = captureSession, captureSession.isRunning else { completion(nil, CameraControllerError.captureSessionIsMissing); return }
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = self.flashMode
        
        self.photoOutput?.capturePhoto(with: settings, delegate: self)
        self.photoCaptureCompletionBlock = completion
    }

    
    
    /**
    Begin recording video of current session
    */
    public func startRecordingVideo() {
        
        guard let device = currentOutputDevcie else {return}
        
        
        if flashMode == .on {
            try? device.lockForConfiguration()
            try? device.setTorchModeOn(level: 1.0)
            device.unlockForConfiguration()
        }
        
        
        guard captureSession?.isRunning == true else {
            print("Cannot start video recoding. Capture session is not running")
            return
        }
        
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }

        sessionQueue.async { [unowned self] in
            if !movieFileOutput.isRecording {
                if UIDevice.current.isMultitaskingSupported {
                    self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }

                // Update the orientation on the movie file output video connection before starting recording.
                let movieFileOutputConnection = self.movieFileOutput?.connection(with: AVMediaType.video)


                //flip video output if front facing camera is selected
                if self.currentCameraPosition == .front {
                    movieFileOutputConnection?.isVideoMirrored = true
                }

                // Start recording to a temporary file.
                let outputFileName = UUID().uuidString
                let outputFilePath = (self.outputFolder as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
                movieFileOutput.startRecording(to: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
                self.isVideoRecording = true
                DispatchQueue.main.async {
                    self.cameraDelegate?.didBeginRecording()
                }
            } else {
                movieFileOutput.stopRecording()
            }
        }
    }

    /**
    Stop video recording video of current session
    
    When video has finished processing, the URL to the video location will be returned by didFinishProcessVideoAt(url:)
    */

    public func stopRecordingVideo() {
        if self.isVideoRecording == true {
            self.isVideoRecording = false
            movieFileOutput!.stopRecording()

            DispatchQueue.main.async {
                self.cameraDelegate?.didFinishRecordingVideo(self)
            }
        }
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
       /// Process newly captured video and write it to temporary directory
    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let currentBackgroundRecordingID = backgroundRecordingID {
            backgroundRecordingID = UIBackgroundTaskIdentifier.invalid

            if currentBackgroundRecordingID != UIBackgroundTaskIdentifier.invalid {
                UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
            }
        }

        if let currentError = error {
            print("Movie file finishing error: \(currentError)")
            DispatchQueue.main.async {
                self.cameraDelegate?.didFailToRecordVideo(self, error: currentError, outputURL: outputFileURL)
                
            }
        } else {
            //Call delegate function with the URL of the outputfile
            DispatchQueue.main.async {
                self.cameraDelegate?.didFinishProcessVideoAt(self, outputFileURL: outputFileURL)
            }
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        if let error = error { self.photoCaptureCompletionBlock?(nil, error) }
            
        else if let data = photo.fileDataRepresentation(),
            let image = UIImage(data: data) {
            self.photoCaptureCompletionBlock?(image, nil)
        } else {
            self.photoCaptureCompletionBlock?(nil, CameraControllerError.unknown)
        }
    }
}

extension CameraController {
    enum CameraControllerError: Swift.Error {
        case captureSessionAlreadyRunning
        case captureSessionIsMissing
        case inputsAreInvalid
        case invalidOperation
        case noCamerasAvailable
        case unknown
    }
    
    public enum CameraPosition {
        case front
        case rear
    }
}
