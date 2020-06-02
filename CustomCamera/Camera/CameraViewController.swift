//
//  CameraViewController.swift
//  CustomCamera
//
//  Created by Austin Betzer on 5/29/20.
//  Copyright © 2020 Austin Betzer. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

/**
 This view will render and handle capturing both photos and vidoes
 
 
 A large portion of the video logic comes from
 https://github.com/Awalz/SwiftyCam/blob/master/Source/SwiftyCamViewController.swift
 */
class CameraViewController: UIViewController {
    
    @IBOutlet private weak var cameraPreviewView: UIView!
    @IBOutlet private weak var switchCameraButton: UIButton!
    @IBOutlet private weak var capturedImageView: UIImageView!
    @IBOutlet private weak var progressBar: CircleProgressBar!
    /// If the play video button is selected that means the video is not currently playing, if the playbutton is not selected then the video player is playing.
    @IBOutlet private weak var eventVideoPlayButton: UIButton!
    @IBOutlet private weak var darkBackgroundImageOverlay: UIView!
    @IBOutlet private weak var centerButtonImageView: UIImageView!
    /// A button that allows the user to download a photo or video, this is hidden until we have one or the other.
    @IBOutlet weak var downloadButton: UIButton!
    @IBOutlet weak var elapsedTimerContainer: UIView!
    @IBOutlet weak var elapsedTimerLabel: UILabel!
    
    
    // MARK: - Properties
    
    /// The current player observer
    private var videoObserver: NSKeyValueObservation?
    
    /// The current player layer
    var eventVideoPlayerLayer: AVPlayerLayer? {
        didSet {
            beginObservingPlayer()
        }
    }
    
    private var capturedPhoto: UIImage? {
        didSet {
            setupViewForCapturedPhoto()
        }
    }
    
    /// This makes the magic happen, configures the camera controller
    private let cameraController = CameraController()
    
    // MARK: - View Life Cycle
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    /// This is used to calulate how full the progress bar is.
    private var tenthsOfaSecond: CGFloat = 1
    
    /// The max video length is configured in 1/10 of a second, so if you divide this number by 10 that is the max length in seconds.
    private var maxVideoLength: CGFloat = 150
    
    private var currentVideoLength: Int = 0
    
    /// The current captured video URL
    private var capturedVideoURL: URL?
    
    /// This is used to time the length of the video
    var videoTimer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        prepareSession()
        setupGestures()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        removeVideoObserversAndStopPlaying()
    }
    
    private func setupGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(capturePhoto(_:)))
        centerButtonImageView.addGestureRecognizer(tapGesture)
        
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(captureVideo(_:)))
        centerButtonImageView.addGestureRecognizer(longPressRecognizer)
    }
    
    @objc func captureVideo(_ sender: UILongPressGestureRecognizer) {
        
        // Setup no photo state
        if  centerButtonImageView.image == UIImage(named: "removePhoto") {
            removeVideoObserversAndStopPlaying()
            resetViewForContentCaputre()
            return
        }
        
        if sender.state == .began {
            print("Capture video")
            cameraController.startRecordingVideo()
            progressBar.isHidden = false
        } else if sender.state == .ended {
            print("End capturing vidoe")
            cameraController.stopRecordingVideo()
            centerButtonImageView.image = UIImage(named: "removePhoto")
            progressBar.isHidden = true
        } else {
//            print("masterclock: \(cameraController.captureSession?.masterClock?.time.seconds)")
//            print("movieFragmentInterval \(cameraController.movieFileOutput?.movieFragmentInterval)")
        }
    }
    
    // MARK: - Actions
    @objc func capturePhoto(_ sender: UITapGestureRecognizer) {
        
        // Setup no photo state
        if  centerButtonImageView.image == UIImage(named: "removePhoto") {
            removeVideoObserversAndStopPlaying()
            resetViewForContentCaputre()
            return
        }
        
        self.capturedPhoto = nil
        // We don't have a photo, so lets capture one
        cameraController.captureImage { (image, error) in
            if let error = error {
                print("Failed to capture photo: \(error.localizedDescription)")
                return
            }
            
            guard let image = image else {return}
            self.capturedPhoto = image
            self.switchCameraButton.isHidden = true
        }
    }
    
    private func removeVideoObserversAndStopPlaying() {
        DispatchQueue.main.async {
            self.eventVideoPlayerLayer?.player?.pause()
            NotificationCenter.default
                .removeObserver(self,
                                name: .AVPlayerItemDidPlayToEndTime,
                                object: self.eventVideoPlayerLayer?.player?.currentItem)
        }
    }
    /**
     Reconfigure the view in preperaion of capturing content
     */
    private func resetViewForContentCaputre() {
        capturedImageView.image = nil
        eventVideoPlayerLayer = nil
        eventVideoPlayerLayer?.removeFromSuperlayer()
        capturedPhoto = nil
        capturedVideoURL = nil
        capturedImageView.isHidden = true
        cameraController.startRunningSession()
        centerButtonImageView.image = UIImage(named: "Ellipse 57")
        tenthsOfaSecond = 1
        progressBar.progress = 0
        switchCameraButton.isHidden = false
        darkBackgroundImageOverlay.alpha = 0
        self.switchCameraButton.isHidden = false
        downloadButton.isHidden = true
    }
    
    @IBAction private func flipCamera(_ sender: Any) {
        do {
          try cameraController.switchCameras()
        } catch(let e) {
            print("Failed to switch cameras: \(e.localizedDescription)")
        }
    }
    
    @IBAction func playPauseVideoButtonTapped(_ sender: Any) {
        // Skip taps if we don't have a player
        guard eventVideoPlayerLayer != nil else {return}
        eventVideoPlayButton.isSelected = !eventVideoPlayButton.isSelected
        togglePlayAndPause()
    }
    
    @IBAction func pinchToZoom(_ pinch: UIPinchGestureRecognizer) {
        cameraController.zoom(pintch: pinch)
    }
    
    @IBAction func downloadButtonTapped(_ sender: Any) {
        if let _ = capturedPhoto {
            downloadImageToDisk()
        } else if let videoURL = capturedVideoURL {
            downloadVideoToDisk(videoURL)
        }
    }
    

    // MARK: - Camera Sesion
    private func togglePlayAndPause() {
        if eventVideoPlayButton.isSelected {
            // the video is selected so play
            DispatchQueue.main.async {
                self.eventVideoPlayerLayer?.player?.pause()
                self.darkBackgroundImageOverlay.alpha = 1
            
            }
            print("**** Player is pausing")
        } else {
            // The video is not selected so we shoudl play
            DispatchQueue.main.async {
                self.darkBackgroundImageOverlay.alpha = 0
                self.eventVideoPlayerLayer?.player?.play()
            }
            print("**** Player is playing")
        }
    }
    
    private func pausePlayer() {
        eventVideoPlayerLayer?.player?.pause()
    }
    
    private func setupViewForCapturedPhoto() {
        if let image = capturedPhoto {
            capturedImageView.image = image
            capturedImageView.isHidden = false
            centerButtonImageView.image = UIImage(named: "removePhoto")
            cameraController.stopCurrentSession()
            switchCameraButton.isHidden = true
            darkBackgroundImageOverlay.alpha = 1
            downloadButton.isHidden = false
        }
    }

    
    private func prepareSession() {
        cameraController.prepare { [weak self] (error) in
            guard let self = self else {return}
            if let error = error {
                print("Faild to load camera: \(error.localizedDescription)")
                return
            }
            
            self.cameraController.cameraDelegate = self
            
            try? self.cameraController.displayPreview(on: self.cameraPreviewView)
        }
    }
    
    private func setupViewToRenderVideo(with videoUrl: URL) {
        let avPlayer = AVPlayer(url: videoUrl)
        self.eventVideoPlayerLayer = AVPlayerLayer(player: avPlayer)
        self.capturedVideoURL = videoUrl
        guard eventVideoPlayerLayer != nil else { return }
        eventVideoPlayerLayer!.frame = capturedImageView.bounds
        capturedImageView.layer.addSublayer(eventVideoPlayerLayer!)
        eventVideoPlayerLayer!.videoGravity = .resizeAspectFill
        eventVideoPlayerLayer?.player?.isMuted = false


        // Setup Video playing state
        capturedImageView.isHidden = false
        darkBackgroundImageOverlay.alpha = 1
        eventVideoPlayButton.isSelected = false
        eventVideoPlayerLayer?.player?.play()
        downloadButton.isHidden = false
    }
    
    private func beginObservingPlayer() {
        guard let player = eventVideoPlayerLayer?.player else {return}
        
        
        self.videoObserver = player.observe(\.status) { (player, status) in
            if player.status == .readyToPlay {
                DispatchQueue.main.async {
                    try? AVAudioSession.sharedInstance().setCategory(.playback)
                }
            }
        }
        
        restartVideoAndPrepareToPlay()
    }
    
    /**
     Prepares the video to play from the beginning
     */
    private func restartVideoAndPrepareToPlay() {
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: self.eventVideoPlayerLayer?.player?.currentItem, queue: .main) { [weak self] _ in
            guard let self = self else {return}
            
            
            self.eventVideoPlayButton.isHidden = true
            self.eventVideoPlayerLayer?.player?.seek(to: CMTime.zero, completionHandler: { (finished) in
                if finished {
                    self.eventVideoPlayerLayer?.player?.play()
                    self.eventVideoPlayButton.isSelected = false
                    self.eventVideoPlayButton.isHidden = false
                }
            })
            
        }
    }
}

// MARK: - Save Video & Photos
extension CameraViewController {

    private func downloadImageToDisk() {
        guard let image = capturedPhoto else {return}
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    
    private func downloadVideoToDisk(_ videoPath: URL) {
        guard UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(videoPath.path) else {return}
        // Handle a movie capture
        UISaveVideoAtPathToSavedPhotosAlbum(videoPath.path,self, #selector(video(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    
    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        let title = (error == nil) ? "Success" : "Error"
        let message = (error == nil) ? "Video was saved" : "Video failed to save"
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
        
    }
    
    @objc func video(_ videoPath: String, didFinishSavingWithError error: Error?, contextInfo info: AnyObject) {
      let title = (error == nil) ? "Success" : "Error"
      let message = (error == nil) ? "Video was saved" : "Video failed to save"
      
      let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
      present(alert, animated: true, completion: nil)
    }
}

// MARK: - CameraDelegate
extension CameraViewController: CameraControllerDelegate {
    
    
    func didFailToRecordVideo(_ cameraController: CameraController, error: Error, outputURL: URL) {
        print("Failed to being recoridng video with err: \(error.localizedDescription)")
        DispatchQueue.main.async { [weak self] in
            self?.videoTimer?.invalidate()
            self?.setupViewToRenderVideo(with: outputURL)
            self?.elapsedTimerContainer.isHidden = true
        }
    }
    
    internal func didBeginRecording() {
        print("didBeginRecording")
        
        elapsedTimerContainer.isHidden = false
        self.switchCameraButton.isHidden = true
        
        // Fires every millisend
        videoTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(0.1), repeats: true, block: { [weak self] (_) in
            self?.tenthsOfaSecond += 1
            let progress = (self?.tenthsOfaSecond ?? 0) / (self?.maxVideoLength ?? 0)
//            print("***** Progress: \(progress)")
            
            
            self?.progressBar.progress = progress

            guard let t = self?.tenthsOfaSecond else {return}
            let time: Double = round(Double(t) / 10)
            print("***** time: \(time)")
            
            // make sure we don't go over 15 seconds
            guard time <= 15 else {return}
            self?.elapsedTimerLabel.text = time.stringDuration
        })
    }
    
    internal func didFinishRecordingVideo(_ cameraController: CameraController) {
        print("didFinishRecordingVideo")
        elapsedTimerContainer.isHidden = true
    }
    
    internal func didFinishProcessVideoAt(_ cameraController: CameraController, outputFileURL: URL) {
        print("didFinishProcessVideoAt output: \(outputFileURL)")
        videoTimer?.invalidate()
        setupViewToRenderVideo(with: outputFileURL)
        elapsedTimerContainer.isHidden = true
        cameraController.stopCurrentSession()
    }
}

extension Double {
    /// Converts the double into a string representing the time elapsed. ex: 80 Seconds converts to 1:20
    var stringDuration: String {
        return convertDoubleToTime()
    }
    
    // Converts a double to a time string.
    private func convertDoubleToTime() -> String {
        let floorCounter = Int(floor(self))
        let minute = (floorCounter % 3600) / 60
        let minuteString = "\(minute)"
        
        let second = (floorCounter % 3600) % 60
        
        var secondString = "\(second)"
        
        if second < 10 {
            secondString = "0\(second)"
        }
        
        return minuteString + ":" + secondString
    }
    
}
