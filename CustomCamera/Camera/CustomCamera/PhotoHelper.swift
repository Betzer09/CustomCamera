//
//  PhotoHelper.swift
//  CustomCamera
//
//  Created by Austin Betzer on 6/2/20.
//  Copyright © 2020 Austin Betzer. All rights reserved.
//

import Foundation
import UIKit

/**
 A class to help with downloading video and photos to disk
 */
class PhotoHelper {
    static func downlaodImageToDisk(_ image: UIImage, vc: UIViewController) {
//        UIImageWriteToSavedPhotosAlbum(image, vc, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
        
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)

    }
    
    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        
        if let error = error {
            print("[PhotoHelper]: Failed to download photo to disk. \n error: \(error.localizedDescription)")
        }
        
    }
}
