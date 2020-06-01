//
//  CameraControllerDelegate.swift
//  CustomCamera
//
//  Created by Austin Betzer on 6/1/20.
//  Copyright © 2020 Austin Betzer. All rights reserved.
//

import Foundation
import AVFoundation

protocol CameraControllerDelegate: class  {
    func didBeginRecording()
    /**
     If you've set a maximun length this delegate will fire if it has reached that lenght, hense the reason will still return the output URL. 
     */
    func didFailToRecordVideo(_ cameraController: CameraController, error: Error, outputURL: URL)
    func didFinishProcessVideoAt(_ cameraController: CameraController, outputFileURL: URL)
    func didFinishRecordingVideo(_ cameraController: CameraController)
}

extension CameraControllerDelegate {
    func didBeginRecording() {}
    func didFailToRecordVideo(_ cameraController: CameraController, error: Error){}
    func didFinishProcessVideoAt(_ cameraController: CameraController, outputFileURL: URL) {}
    func didFinishRecordingVideo(_ cameraController: CameraController, outputFileURL: URL) {}
}
