//  AutoScreenshotContentView.swift
//  Automatic object detection

import SwiftUI
import RealityKit
import ARKit
import AVFoundation
import MediaPipeTasksVision

// Main SwiftUI view
struct AutoScreenshotContentView: View {
    var body: some View {
        AutoScreenshotARViewContainer()
            .edgesIgnoringSafeArea(.all)
    }
}

// Embed UIKit views (ARView) into SwiftUI
struct AutoScreenshotARViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Configure AR world tracking
        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .automatic
        config.planeDetection = [.horizontal]
        arView.session.run(config)

        context.coordinator.arView = arView
        context.coordinator.setupObjectDetector() // object detection
        context.coordinator.startCameraCapture() // capture camera feeds to feed into MediaPipe

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // Handles camera and object detection logic
    class Coordinator: NSObject {
        weak var arView: ARView?

        private var objectDetector: ObjectDetector? // MediaPipe object detector instance
        private var captureSession: AVCaptureSession? // Camera capture session

        // Object detection
        func setupObjectDetector() {
            do {
                let baseOptions = BaseOptions()
                baseOptions.modelAssetPath = "efficientdet_lite0.tflite" // TODO: replace file?
                                
                let options = ObjectDetectorOptions()
                options.baseOptions = baseOptions
                options.runningMode = MediaPipeTasksVision.RunningMode.liveStream   // live camera feed mode
                options.maxResults = 1  // max num of objects to detect per frame
                options.scoreThreshold = 0.5    // min. confidence threshold

                objectDetector = try ObjectDetector(options: options)

                print("MediaPipe ObjectDetector initialized")
            } catch {
                print("Failed to initialize ObjectDetector: \(error)")
            }
        }

        // Camera capture session
        func startCameraCapture() {
            captureSession = AVCaptureSession()
            guard let captureSession = captureSession else { return }

            // Use back camera as video input device
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("Back camera not found")
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device) // add camera input to session
                captureSession.addInput(input)
            } catch {
                print("Camera input error: \(error)")
                return
            }

            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_queue"))
            captureSession.addOutput(output)

            captureSession.startRunning() // run camera session async
            print("Camera started")
        }
    }
}

extension AutoScreenshotARViewContainer.Coordinator: AVCaptureVideoDataOutputSampleBufferDelegate {
    // Called for every video frame
//    func captureOutput(_ output: AVCaptureOutput,
//                       didOutput sampleBuffer: CMSampleBuffer,
//                       from connection: AVCaptureConnection) {
//        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
//              let detector = objectDetector else { return }
//        
//        // Create MPImage from pixel buffer with error handling
//        guard let mpImage = try? MPImage(pixelBuffer: pixelBuffer) else {
//            print("Failed to create MPImage")
//            return
//        }
//
//        let timestampMs = Int(Date().timeIntervalSince1970 * 1000)
//
//        detector.detectAsync(image: mpImage, timestampInMilliseconds: timestampMs)
//        
//        
////        detector.detectAsync(image: mpImage, timestampInMilliseconds: timestampMs) { result, error in
////            if let error = error {
////                print("Detection error: \(error.localizedDescription)")
////                return
////            }
////
////            // Extract detections
////            guard let detections = result?.detections else { return }
////
////            // Check each detection
////            for detection in detections {
////                if let category = detection.categories.first,
////                   category.categoryName.lowercased() == "book",
////                   category.score > 0.5 {
////                    print("Book detected! Confidence: \(category.score)")
////                }
////            }
////        }
//    }
    
    func captureOutput(_ output: AVCaptureOutput,
                           didOutput sampleBuffer: CMSampleBuffer,
                           from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let detector = objectDetector else { return }

        // Create MPImage without error handling (force unwrap)
        guard let mpImage = try? MPImage(pixelBuffer: pixelBuffer) else {
            print("Failed to create MPImage")
            return
        }

        // Synchronously detect objects in this frame (no callback)
        guard let result = try? detector.detect(image: mpImage) else {
            print("Detection failed")
            return
        }

        let detections = result.detections

        for detection in detections {
            if let category = detection.categories.first,
               category.categoryName?.lowercased() == "book",
               category.score > 0.5 {
                print("Book detected! Confidence: \(category.score)")
            }
        }
    }

}
