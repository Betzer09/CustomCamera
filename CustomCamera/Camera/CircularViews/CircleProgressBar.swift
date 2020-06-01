//
//  CircleProgressBar.swift
//  CustomCamera
//
//  Created by Austin Betzer on 5/29/20.
//  Copyright © 2020 Austin Betzer. All rights reserved.
//

import Foundation
import UIKit

@IBDesignable
class CircleProgressBar: UIView {
    @IBInspectable var color: UIColor? = .blue {
        didSet { setNeedsDisplay() }
    }
    @IBInspectable var ringWidth: CGFloat = 5

    /// The progress between 0 - 1
    var progress: CGFloat = 0 {
        didSet { setNeedsDisplay() }
    }

    private var progressLayer = CAShapeLayer()
    private var backgroundMask = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()

    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    private func setupLayers() {
        backgroundMask.lineWidth = ringWidth
        backgroundMask.fillColor = nil
        backgroundMask.strokeColor = UIColor.white.cgColor
        layer.mask = backgroundMask

        progressLayer.lineWidth = ringWidth
        progressLayer.fillColor = nil
        layer.addSublayer(progressLayer)
        layer.transform = CATransform3DMakeRotation(CGFloat(90 * Double.pi / 180), 0, 0, -1)
        
        let backgroundView = UIView()
        backgroundView.frame = self.frame
        backgroundView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        backgroundView.backgroundColor = .systemPink
        self.insertSubview(backgroundView, aboveSubview: self)
    }

    override func draw(_ rect: CGRect) {
        let circlePath = UIBezierPath(ovalIn: rect.insetBy(dx: ringWidth / 2, dy: ringWidth / 2))
        backgroundMask.path = circlePath.cgPath

        progressLayer.path = circlePath.cgPath
        progressLayer.lineCap = .round
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = progress
        progressLayer.strokeColor = color?.cgColor
    }
}

