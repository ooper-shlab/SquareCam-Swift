//
//  SquareCamViewController.swift
//  SquareCam 
//
//  Translated by OOPer in cooperation with shlab.jp, on 2014/10/05.
//
//
/*
     File: SquareCamViewController.h
     File: SquareCamViewController.m
 Abstract: Dmonstrates iOS 5 features of the AVCaptureStillImageOutput class
  Version: 1.0

 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.

 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.

 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.

 Copyright (C) 2013 Apple Inc. All Rights Reserved.

 */

import UIKit
import AVFoundation
import CoreImage
import ImageIO
import AssetsLibrary

//MARK:-

// used for KVO observation of the @"capturingStillImage" property to perform flash bulb animation
private var AVCaptureStillImageIsCapturingStillImageContext_ = 0

private func DegreesToRadians(degrees: CGFloat) -> CGFloat {return degrees * CGFloat(M_PI / 180)}

private func ReleaseCVPixelBuffer(pixel: CVPixelBuffer, data: UnsafePointer<Void>, size: Int) {
    CVPixelBufferUnlockBaseAddress(pixel, 0)
}

// create a CGImage with provided pixel buffer, pixel buffer must be uncompressed kCVPixelFormatType_32ARGB or kCVPixelFormatType_32BGRA
private func CreateCGImageFromCVPixelBuffer(pixelBuffer: CVPixelBuffer, inout _ imageOut: CGImage?) -> OSStatus {
    let err = noErr
    var bitmapInfo: CGBitmapInfo
    
    let sourcePixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
    if kCVPixelFormatType_32ARGB == sourcePixelFormat {
        bitmapInfo = CGBitmapInfo.ByteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.NoneSkipFirst.rawValue))
    } else if kCVPixelFormatType_32BGRA == sourcePixelFormat {
        bitmapInfo = CGBitmapInfo.ByteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.NoneSkipFirst.rawValue))
    } else {
        return -95014 // only uncompressed pixel formats
    }
    
    let sourceRowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0)
    let sourceBaseAddr = CVPixelBufferGetBaseAddress(pixelBuffer)
    
    let colorspace = CGColorSpaceCreateDeviceRGB()
    
    let data = NSData(bytes: sourceBaseAddr, length: sourceRowBytes * height)
    let provider = CGDataProviderCreateWithCFData(data)
    let image = CGImageCreate(width, height, 8, 32, sourceRowBytes, colorspace, bitmapInfo, provider, nil, true, CGColorRenderingIntent.RenderingIntentDefault)
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0)
    
    imageOut = image
    return err
}

// utility used by newSquareOverlayedImageForFeatures for
func CreateCGBitmapContextForSize(size: CGSize) -> CGContext? {
    
    let bitmapBytesPerRow = Int(size.width * 4)
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGBitmapContextCreate(nil,
        Int(size.width),
        Int(size.height),
        8,      // bits per component
        bitmapBytesPerRow,
        colorSpace,
        CGImageAlphaInfo.PremultipliedLast.rawValue)
    CGContextSetAllowsAntialiasing(context, false)
    return context
}

//MARK:-

extension UIImage {
    
    func imageRotatedByDegrees(degrees: CGFloat) -> UIImage! {
        // calculate the size of the rotated view's containing box for our drawing space
        let rotatedViewBox = UIView(frame: CGRectMake(0, 0, self.size.width, self.size.height))
        let t = CGAffineTransformMakeRotation(DegreesToRadians(degrees))
        rotatedViewBox.transform = t
        let rotatedSize = rotatedViewBox.frame.size
        
        // Create the bitmap context
        UIGraphicsBeginImageContext(rotatedSize)
        let bitmap = UIGraphicsGetCurrentContext()
        
        // Move the origin to the middle of the image so we will rotate and scale around the center.
        CGContextTranslateCTM(bitmap, rotatedSize.width/2, rotatedSize.height/2)
        
        //   // Rotate the image context
        CGContextRotateCTM(bitmap, DegreesToRadians(degrees))
        
        // Now, draw the rotated/scaled image into the context
        CGContextScaleCTM(bitmap, 1.0, -1.0)
        CGContextDrawImage(bitmap, CGRectMake(-self.size.width / 2, -self.size.height / 2, self.size.width, self.size.height), self.CGImage)
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
        
    }
    
}

//MARK:-

@objc(SquareCamViewController)
class SquareCamViewController: UIViewController, UIGestureRecognizerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    @IBOutlet private var previewView: UIView!
    @IBOutlet private var camerasControl: UISegmentedControl!
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var detectFaces: Bool = false
    private var videoDataOutputQueue: dispatch_queue_t?
    private var stillImageOutput: AVCaptureStillImageOutput?
    private var flashView: UIView?
    private var square: UIImage!
    private var isUsingFrontFacingCamera: Bool = false
    private var faceDetector: CIDetector!
    private var beginGestureScale: CGFloat = 0.0
    private var effectiveScale: CGFloat = 0.0
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    private func setupAVCapture() {
        do {
            
            let session = AVCaptureSession()
            if UIDevice.currentDevice().userInterfaceIdiom == .Phone {
                session.sessionPreset = AVCaptureSessionPreset640x480
            } else {
                session.sessionPreset = AVCaptureSessionPresetPhoto
            }
            
            // Select a video device, make an input
            let device = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
            let deviceInput = try AVCaptureDeviceInput(device: device)
            
            isUsingFrontFacingCamera = false
            if session.canAddInput(deviceInput) {
                session.addInput(deviceInput)
            }
            
            // Make a still image output
            stillImageOutput = AVCaptureStillImageOutput()
            stillImageOutput!.addObserver(self, forKeyPath: "capturingStillImage", options:.New, context: &AVCaptureStillImageIsCapturingStillImageContext_)
            if session.canAddOutput(stillImageOutput) {
                session.addOutput(stillImageOutput)
            }
            
            // Make a video data output
            videoDataOutput = AVCaptureVideoDataOutput()
            
            // we want BGRA, both CoreGraphics and OpenGL work well with 'BGRA'
            let rgbOutputSettings: [String: AnyObject] = [kCVPixelBufferPixelFormatTypeKey as String: kCMPixelFormat_32BGRA.l]
            videoDataOutput!.videoSettings = rgbOutputSettings
            videoDataOutput!.alwaysDiscardsLateVideoFrames = true // discard if the data output queue is blocked (as we process the still image)
            
            // create a serial dispatch queue used for the sample buffer delegate as well as when a still image is captured
            // a serial dispatch queue must be used to guarantee that video frames will be delivered in order
            // see the header doc for setSampleBufferDelegate:queue: for more information
            videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL)
            videoDataOutput!.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
            
            if session.canAddOutput(videoDataOutput) {
                session.addOutput(videoDataOutput)
            }
            videoDataOutput!.connectionWithMediaType(AVMediaTypeVideo).enabled = false
            
            effectiveScale = 1.0;
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer!.backgroundColor = UIColor.blackColor().CGColor
            previewLayer!.videoGravity = AVLayerVideoGravityResizeAspect
            let rootLayer = previewView.layer
            rootLayer.masksToBounds = true
            previewLayer!.frame = rootLayer.bounds
            rootLayer.addSublayer(previewLayer!)
            session.startRunning()
            
        } catch let error as NSError {
            if #available(iOS 8.0, *) {
                let alertController = UIAlertController(title: "Failed with error \(error.code)", message: error.description, preferredStyle: .Alert)
                let dismissAction = UIAlertAction(title: "Dismiss", style: .Cancel, handler: nil)
                alertController.addAction(dismissAction)
                self.presentViewController(alertController, animated: true, completion: nil)
            } else {
                let alertView = UIAlertView(title: "Failed with error \(error.code)",
                    message: error.description,
                    delegate: nil,
                    cancelButtonTitle: "Dismiss")
                alertView.show()
            }
            self.teardownAVCapture()
        }
    }
    
    // clean up capture setup
    private func teardownAVCapture() {
        videoDataOutput = nil
        if videoDataOutputQueue != nil {
            videoDataOutputQueue = nil
        }
        stillImageOutput?.removeObserver(self, forKeyPath: "isCapturingStillImage")
        stillImageOutput = nil
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }
    
    // perform a flash bulb animation using KVO to monitor the value of the capturingStillImage property of the AVCaptureStillImageOutput class
    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        if context == &AVCaptureStillImageIsCapturingStillImageContext_ {
            let isCapturingStillImage = change![NSKeyValueChangeNewKey] as! Bool
            
            if isCapturingStillImage {
                // do flash bulb like animation
                flashView = UIView(frame: previewView!.frame)
                flashView!.backgroundColor = UIColor.whiteColor()
                flashView!.alpha = 0.0
                self.view.window?.addSubview(flashView!)
                
                UIView.animateWithDuration(0.4) {
                    self.flashView?.alpha = 1.0
                }
            } else {
                UIView.animateWithDuration(0.4,
                    animations: {
                        self.flashView?.alpha = 0.0
                    },
                    completion: {finished in
                        self.flashView?.removeFromSuperview()
                        self.flashView = nil;
                })
            }
        }
    }
    
    // utility routing used during image capture to set up capture orientation
    private func avOrientationForDeviceOrientation(deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation {
        var result = AVCaptureVideoOrientation(rawValue: deviceOrientation.rawValue)!
        if deviceOrientation == UIDeviceOrientation.LandscapeLeft {
            result = AVCaptureVideoOrientation.LandscapeRight
        } else if deviceOrientation == UIDeviceOrientation.LandscapeRight {
            result = AVCaptureVideoOrientation.LandscapeLeft
        }
        return result
    }
    
    // utility routine to create a new image with the red square overlay with appropriate orientation
    // and return the new composited image which can be saved to the camera roll
    private func newSquareOverlayedImageForFeatures(features: [CIFeature],
        inCGImage backgroundImage: CGImage,
        withOrientation orientation: UIDeviceOrientation,
        frontFacing isFrontFacing: Bool) -> CGImage
    {
        let backgroundImageRect = CGRectMake(0.0, 0.0, CGImageGetWidth(backgroundImage).g, CGImageGetHeight(backgroundImage).g)
        let bitmapContext = CreateCGBitmapContextForSize(backgroundImageRect.size)
        CGContextClearRect(bitmapContext, backgroundImageRect)
        CGContextDrawImage(bitmapContext, backgroundImageRect, backgroundImage)
        var rotationDegrees: CGFloat = 0.0
        
        switch orientation {
        case .Portrait:
            rotationDegrees = -90.0
        case .PortraitUpsideDown:
            rotationDegrees = 90.0
        case .LandscapeLeft:
            if isFrontFacing {
                rotationDegrees = 180.0
            } else {
                rotationDegrees = 0.0
            }
        case .LandscapeRight:
            if isFrontFacing {
                rotationDegrees = 0.0
            } else {
                rotationDegrees = 180.0
            }
        case .FaceUp, .FaceDown:
            break
        default:
            break // leave the layer in its last known orientation
        }
        let rotatedSquareImage = square.imageRotatedByDegrees(rotationDegrees)
        
        // features found by the face detector
        for ff in features {
            let faceRect = ff.bounds
            CGContextDrawImage(bitmapContext, faceRect, rotatedSquareImage.CGImage)
        }
        let returnImage = CGBitmapContextCreateImage(bitmapContext)!
        
        return returnImage
    }
    
    // utility routine used after taking a still image to write the resulting image to the camera roll
    private func writeCGImageToCameraRoll(cgImage: CGImage, withMetadata metadata: [String: AnyObject]) -> Bool {
        var success = true
        bail: do {
            let destinationData = CFDataCreateMutable(kCFAllocatorDefault, 0)
            guard let destination = CGImageDestinationCreateWithData(destinationData,
                "public.jpeg",
                1,
                nil)
                else {
                    success = false
                    break bail
            }
            
            let JPEGCompQuality: Float = 0.85 // JPEGHigherQuality
            
            let optionsDict: [NSObject: AnyObject] = [
                kCGImageDestinationLossyCompressionQuality: JPEGCompQuality,
            ]
            
            CGImageDestinationAddImage(destination, cgImage, optionsDict)
            success = CGImageDestinationFinalize(destination)
            
            guard success else {break bail}
            
            let library = ALAssetsLibrary()
            library.writeImageDataToSavedPhotosAlbum(destinationData, metadata: metadata) {assetURL, error in
            }
            
            
        }
        return success
    }
    
    // utility routine to display error aleart if takePicture fails
    private func displayErrorOnMainQueue(error: NSError, withMessage message: String) {
        dispatch_async(dispatch_get_main_queue()) {
            if #available(iOS 8.0, *) {
                let alertController = UIAlertController(title:  "\(message) (\(error.code)", message: error.localizedDescription, preferredStyle: .Alert)
                let dismissAction = UIAlertAction(title: "Dismiss", style: .Cancel, handler: nil)
                alertController.addAction(dismissAction)
                self.presentViewController(alertController, animated: true, completion: nil)
            } else {
                let alertView = UIAlertView(title: "\(message) (\(error.code)", message: error.localizedDescription, delegate: nil, cancelButtonTitle: "Dismiss")
                alertView.show()
            }
        }
    }
    
    // main action method to take a still image -- if face detection has been turned on and a face has been detected
    // the square overlay will be composited on top of the captured image and saved to the camera roll
    @IBAction func takePicture(_: AnyObject) {
        // Find out the current orientation and tell the still image output.
        let stillImageConnection = stillImageOutput!.connectionWithMediaType(AVMediaTypeVideo)
        let curDeviceOrientation = UIDevice.currentDevice().orientation
        let avcaptureOrientation = self.avOrientationForDeviceOrientation(curDeviceOrientation)
        stillImageConnection.videoOrientation = avcaptureOrientation
        stillImageConnection.videoScaleAndCropFactor = effectiveScale
        
        let doingFaceDetection = detectFaces && (effectiveScale == 1.0)
        
        // set the appropriate pixel format / image type output setting depending on if we'll need an uncompressed image for
        // the possiblity of drawing the red square over top or if we're just writing a jpeg to the camera roll which is the trival case
        if doingFaceDetection {
            stillImageOutput!.outputSettings = [kCVPixelBufferPixelFormatTypeKey: kCMPixelFormat_32BGRA.l]
        } else {
            stillImageOutput!.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
        }
        
        stillImageOutput!.captureStillImageAsynchronouslyFromConnection(stillImageConnection) {
            imageDataSampleBuffer, error in
            if error != nil {
                self.displayErrorOnMainQueue(error!, withMessage: "Take picture failed")
            } else {
                if doingFaceDetection {
                    // Got an image.
                    let pixelBuffer = CMSampleBufferGetImageBuffer(imageDataSampleBuffer)!
                    let attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, imageDataSampleBuffer, kCMAttachmentMode_ShouldPropagate) as NSDictionary? as! [String: AnyObject]?
                    let ciImage = CIImage(CVPixelBuffer: pixelBuffer, options: attachments)
                    
                    var imageOptions: [String: AnyObject] = [:]
                    if let orientation = CMGetAttachment(imageDataSampleBuffer, kCGImagePropertyOrientation, nil) {
                        imageOptions = [CIDetectorImageOrientation: orientation]
                    }
                    
                    // when processing an existing frame we want any new frames to be automatically dropped
                    // queueing this block to execute on the videoDataOutputQueue serial queue ensures this
                    // see the header doc for setSampleBufferDelegate:queue: for more information
                    dispatch_sync(self.videoDataOutputQueue!) {
                        
                        // get the array of CIFeature instances in the given image with a orientation passed in
                        // the detection will be done based on the orientation but the coordinates in the returned features will
                        // still be based on those of the image.
                        let features = self.faceDetector.featuresInImage(ciImage, options: imageOptions)
                        var srcImage: CGImage? = nil
                        let err = CreateCGImageFromCVPixelBuffer(CMSampleBufferGetImageBuffer(imageDataSampleBuffer)!, &srcImage)
                        if err != noErr {fatalError()}
                        
                        let cgImageResult = self.newSquareOverlayedImageForFeatures(features, inCGImage: srcImage!, withOrientation: curDeviceOrientation, frontFacing: self.isUsingFrontFacingCamera)
                        
                        let attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault,
                            imageDataSampleBuffer,
                            kCMAttachmentMode_ShouldPropagate) as NSDictionary? as! [String: AnyObject]
                        self.writeCGImageToCameraRoll(cgImageResult, withMetadata: attachments)
                        
                    }
                    
                } else {
                    // trivial simple JPEG case
                    let jpegData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                    let attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault,
                        imageDataSampleBuffer,
                        kCMAttachmentMode_ShouldPropagate) as NSDictionary? as! [NSObject: AnyObject]
                    let library = ALAssetsLibrary()
                    library.writeImageDataToSavedPhotosAlbum(jpegData, metadata: attachments) {assetURL, error in
                        if let error = error {
                            self.displayErrorOnMainQueue(error, withMessage: "Save to camera roll failed")
                        }
                    }
                    
                }
            }
        }
    }
    
    // turn on/off face detection
    @IBAction func toggleFaceDetection(sender: UISwitch) {
        detectFaces = sender.on
        videoDataOutput?.connectionWithMediaType(AVMediaTypeVideo).enabled = detectFaces
        if !detectFaces {
            dispatch_async(dispatch_get_main_queue()) {
                // clear out any squares currently displaying.
                self.drawFaceBoxesForFeatures([], forVideoBox: CGRectZero, orientation: .Portrait)
            }
        }
    }
    
    // find where the video box is positioned within the preview layer based on the video size and gravity
    private static func videoPreviewBoxForGravity(gravity: String, frameSize: CGSize, apertureSize: CGSize) -> CGRect {
        let apertureRatio = apertureSize.height / apertureSize.width
        let viewRatio = frameSize.width / frameSize.height
        
        var size = CGSizeZero
        switch gravity {
        case AVLayerVideoGravityResizeAspectFill:
            if viewRatio > apertureRatio {
                size.width = frameSize.width
                size.height = apertureSize.width * (frameSize.width / apertureSize.height)
            } else {
                size.width = apertureSize.height * (frameSize.height / apertureSize.width)
                size.height = frameSize.height
            }
        case AVLayerVideoGravityResizeAspect:
            if viewRatio > apertureRatio {
                size.width = apertureSize.height * (frameSize.height / apertureSize.width)
                size.height = frameSize.height;
            } else {
                size.width = frameSize.width;
                size.height = apertureSize.width * (frameSize.width / apertureSize.height);
            }
        case AVLayerVideoGravityResize:
            size.width = frameSize.width
            size.height = frameSize.height
        default:
            break
        }
        
        var videoBox: CGRect = CGRect()
        videoBox.size = size;
        if size.width < frameSize.width {
            videoBox.origin.x = (frameSize.width - size.width) / 2
        } else {
            videoBox.origin.x = (size.width - frameSize.width) / 2
        }
        
        if size.height < frameSize.height {
            videoBox.origin.y = (frameSize.height - size.height) / 2
        } else {
            videoBox.origin.y = (size.height - frameSize.height) / 2
        }
        
        return videoBox;
    }
    
    // called asynchronously as the capture output is capturing sample buffers, this method asks the face detector (if on)
    // to detect features and for each draw the red square in a layer and set appropriate orientation
    private func drawFaceBoxesForFeatures(features: [CIFeature], forVideoBox clap: CGRect, orientation: UIDeviceOrientation) {
        let sublayers = previewLayer?.sublayers ?? []
        let sublayersCount = sublayers.count
        var currentSublayer = 0
        var featuresCount = features.count, currentFeature = 0
        
        CATransaction.begin()
        CATransaction.setValue(true, forKey: kCATransactionDisableActions)
        
        // hide all the face layers
        for layer in sublayers {
            if layer.name == "FaceLayer" {
                layer.hidden = true
            }
        }
        
        if featuresCount == 0 || !detectFaces {
            CATransaction.commit()
            return // early bail.
        }
        
        let parentFrameSize = previewView.frame.size;
        let gravity = previewLayer?.videoGravity
        let isMirrored = previewLayer?.connection.videoMirrored ?? false
        let previewBox = SquareCamViewController.videoPreviewBoxForGravity(gravity!,
            frameSize: parentFrameSize,
            apertureSize: clap.size)
        
        for ff in features as! [CIFaceFeature] {
            // find the correct position for the square layer within the previewLayer
            // the feature box originates in the bottom left of the video frame.
            // (Bottom right if mirroring is turned on)
            var faceRect = ff.bounds
            
            // flip preview width and height
            var temp = faceRect.size.width
            faceRect.size.width = faceRect.size.height
            faceRect.size.height = temp
            temp = faceRect.origin.x
            faceRect.origin.x = faceRect.origin.y
            faceRect.origin.y = temp
            // scale coordinates so they fit in the preview box, which may be scaled
            let widthScaleBy = previewBox.size.width / clap.size.height
            let heightScaleBy = previewBox.size.height / clap.size.width
            faceRect.size.width *= widthScaleBy
            faceRect.size.height *= heightScaleBy
            faceRect.origin.x *= widthScaleBy
            faceRect.origin.y *= heightScaleBy
            
            if isMirrored {
                faceRect = CGRectOffset(faceRect, previewBox.origin.x + previewBox.size.width - faceRect.size.width - (faceRect.origin.x * 2), previewBox.origin.y)
            } else {
                faceRect = CGRectOffset(faceRect, previewBox.origin.x, previewBox.origin.y)
            }
            
            var featureLayer: CALayer? = nil
            
            // re-use an existing layer if possible
            while featureLayer == nil && (currentSublayer < sublayersCount) {
                let currentLayer = sublayers[currentSublayer];currentSublayer += 1
                if currentLayer.name == "FaceLayer" {
                    featureLayer = currentLayer
                    currentLayer.hidden = false
                }
            }
            
            // create a new one if necessary
            if featureLayer == nil {
                featureLayer = CALayer()
                featureLayer!.contents = square.CGImage
                featureLayer!.name = "FaceLayer"
                previewLayer?.addSublayer(featureLayer!)
            }
            featureLayer!.frame = faceRect
            
            switch orientation {
            case .Portrait:
                featureLayer!.setAffineTransform(CGAffineTransformMakeRotation(DegreesToRadians(0.0)))
            case .PortraitUpsideDown:
                featureLayer!.setAffineTransform(CGAffineTransformMakeRotation(DegreesToRadians(180.0)))
            case .LandscapeLeft:
                featureLayer!.setAffineTransform(CGAffineTransformMakeRotation(DegreesToRadians(90.0)))
            case .LandscapeRight:
                featureLayer!.setAffineTransform(CGAffineTransformMakeRotation(DegreesToRadians(-90.0)))
            case .FaceUp, .FaceDown:
                break
            default:
                
                break // leave the layer in its last known orientation//		}
            }
            currentFeature += 1
        }
        
        CATransaction.commit()
    }
    
    func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        // got an image
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        let attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate) as NSDictionary? as! [String: AnyObject]?
        let ciImage = CIImage(CVPixelBuffer: pixelBuffer, options: attachments)
        let curDeviceOrientation = UIDevice.currentDevice().orientation
        var exifOrientation: Int = 0
        
        /* kCGImagePropertyOrientation values
        The intended display orientation of the image. If present, this key is a CFNumber value with the same value as defined
        by the TIFF and EXIF specifications -- see enumeration of integer constants.
        The value specified where the origin (0,0) of the image is located. If not present, a value of 1 is assumed.
        
        used when calling featuresInImage: options: The value for this key is an integer NSNumber from 1..8 as found in kCGImagePropertyOrientation.
        If present, the detection will be done based on that orientation but the coordinates in the returned features will still be based on those of the image. */
        
        
        let PHOTOS_EXIF_0ROW_TOP_0COL_LEFT			= 1 //   1  =  0th row is at the top, and 0th column is on the left (THE DEFAULT).
        //let PHOTOS_EXIF_0ROW_TOP_0COL_RIGHT			= 2 //   2  =  0th row is at the top, and 0th column is on the right.
        let PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT      = 3 //   3  =  0th row is at the bottom, and 0th column is on the right.
        //let PHOTOS_EXIF_0ROW_BOTTOM_0COL_LEFT       = 4 //   4  =  0th row is at the bottom, and 0th column is on the left.
        //let PHOTOS_EXIF_0ROW_LEFT_0COL_TOP          = 5 //   5  =  0th row is on the left, and 0th column is the top.
        let PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP         = 6 //   6  =  0th row is on the right, and 0th column is the top.
        //let PHOTOS_EXIF_0ROW_RIGHT_0COL_BOTTOM      = 7 //   7  =  0th row is on the right, and 0th column is the bottom.
        let PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM       = 8  //   8  =  0th row is on the left, and 0th column is the bottom.
        
        switch curDeviceOrientation {
        case .PortraitUpsideDown:  // Device oriented vertically, home button on the top
            exifOrientation = PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM
        case .LandscapeLeft:       // Device oriented horizontally, home button on the right
            if isUsingFrontFacingCamera {
                exifOrientation = PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT
            } else {
                exifOrientation = PHOTOS_EXIF_0ROW_TOP_0COL_LEFT
            }
        case .LandscapeRight:      // Device oriented horizontally, home button on the left
            if isUsingFrontFacingCamera {
                exifOrientation = PHOTOS_EXIF_0ROW_TOP_0COL_LEFT
            } else {
                exifOrientation = PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT
            }
        case .Portrait:            // Device oriented vertically, home button on the bottom
            fallthrough
        default:
            exifOrientation = PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP
        }
        
        let imageOptions = [CIDetectorImageOrientation: exifOrientation]
        let features = faceDetector.featuresInImage(ciImage, options: imageOptions)
        
        // get the clean aperture
        // the clean aperture is a rectangle that defines the portion of the encoded pixel dimensions
        // that represents image data valid for display.
        let fdesc = CMSampleBufferGetFormatDescription(sampleBuffer)!
        let clap = CMVideoFormatDescriptionGetCleanAperture(fdesc, false /*originIsTopLeft == false*/)
        
        dispatch_async(dispatch_get_main_queue()) {
            self.drawFaceBoxesForFeatures(features, forVideoBox: clap, orientation: curDeviceOrientation)
        }
    }
    
    deinit {
        self.teardownAVCapture()
    }
    
    // use front/back camera
    @IBAction func switchCameras(_: AnyObject) {
        let desiredPosition: AVCaptureDevicePosition
        if isUsingFrontFacingCamera {
            desiredPosition = AVCaptureDevicePosition.Back
        } else {
            desiredPosition = AVCaptureDevicePosition.Front
        }
        
        for d in AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo) as! [AVCaptureDevice] {
            if d.position == desiredPosition {
                previewLayer?.session.beginConfiguration()
                var input: AVCaptureDeviceInput?
                do {
                    input = try AVCaptureDeviceInput(device: d)
                } catch {}
                for oldInput in previewLayer?.session.inputs as! [AVCaptureInput]! ?? [] {
                    previewLayer?.session.removeInput(oldInput)
                }
                previewLayer?.session.addInput(input)
                previewLayer?.session.commitConfiguration()
            }
        }
        isUsingFrontFacingCamera = !isUsingFrontFacingCamera
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    //MARK: - View lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        self.setupAVCapture()
        square = UIImage(named: "squarePNG")
        let detectorOptions: [String: AnyObject] = [CIDetectorAccuracy: CIDetectorAccuracyLow]
        faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: detectorOptions)
    }
    
    //- (void)viewDidUnload
    //{
    //    [super viewDidUnload];
    //    // Release any retained subviews of the main view.
    //    // e.g. self.myOutlet = nil;
    //}
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    //- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
    //{
    //    // Return YES for supported orientations
    //	return (interfaceOrientation == UIInterfaceOrientationPortrait);
    //}
    override func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        return .Portrait
    }
    override func preferredInterfaceOrientationForPresentation() -> UIInterfaceOrientation {
        return .Portrait
    }
    
    func gestureRecognizerShouldBegin(gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UIPinchGestureRecognizer {
            beginGestureScale = effectiveScale
        }
        return true
    }
    
    // scale image depending on users pinch gesture
    @IBAction func handlePinchGesture(recognizer: UIPinchGestureRecognizer) {
        var allTouchesAreOnThePreviewLayer = true
        let numTouches = recognizer.numberOfTouches()
        for i in 0..<numTouches {
            let location = recognizer.locationOfTouch(i, inView: previewView)
            let convertedLocation = previewLayer!.convertPoint(location, fromLayer: previewLayer!.superlayer)
            if !previewLayer!.containsPoint(convertedLocation) {
                allTouchesAreOnThePreviewLayer = false
                break
            }
        }
        
        if allTouchesAreOnThePreviewLayer {
            effectiveScale = beginGestureScale * recognizer.scale
            if effectiveScale < 1.0 {
                effectiveScale = 1.0
            }
            let maxScaleAndCropFactor = stillImageOutput!.connectionWithMediaType(AVMediaTypeVideo).videoMaxScaleAndCropFactor
            if effectiveScale > maxScaleAndCropFactor {
                effectiveScale = maxScaleAndCropFactor
            }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.025)
            previewLayer!.setAffineTransform(CGAffineTransformMakeScale(effectiveScale, effectiveScale))
            CATransaction.commit()
        }
    }
    
}