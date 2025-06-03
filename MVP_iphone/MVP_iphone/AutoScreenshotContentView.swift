//  AutoScreenshotContentView.swift
//  Automatic object detection

import SwiftUI
import RealityKit
import ARKit
import AVFoundation
import MediaPipeTasksVision
import UIKit

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

        arView.session.delegate = context.coordinator // handle camera freezing
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
    class Coordinator: NSObject, ObjectDetectorLiveStreamDelegate, ARSessionDelegate {
        weak var arView: ARView?

        private var objectDetector: ObjectDetector? // MediaPipe object detector instance
        private var captureSession: AVCaptureSession? // Camera capture session
        
        private var lastDetectionTime: TimeInterval = 0
        private let detectionInterval: TimeInterval = 0.3

        // Set up object detector
        func setupObjectDetector() {
            do {
                let baseOptions = BaseOptions()
                baseOptions.modelAssetPath = "efficientdet_lite0.tflite"
                
                let options = ObjectDetectorOptions()
                options.baseOptions = baseOptions
                options.runningMode = .liveStream   // live camera feed mode
                options.maxResults = 1  // max num of objects to detect per frame
                options.scoreThreshold = 0.4    // min. confidence threshold
                
                options.objectDetectorLiveStreamDelegate = self
                
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
            
             // Added to address error "Unsupported pixel format for CVPixelBuffer. Expected kCVPixelFormatType_32BGRA"
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_queue"))
            captureSession.addOutput(output)

            captureSession.startRunning() // run camera session async
            print("Camera started")
        }
        
        // Procsss frame detections
        func objectDetector(_ objectDetector: ObjectDetector,
                            didFinishDetection result: ObjectDetectorResult?,
                            timestampInMilliseconds: Int,
                            error: Error?) {
            if let error = error {
                print("Detection error: \(error)")
                return
            }

            guard let result = result else {
                print("No detection result")
                return
            }

            for detection in result.detections {
                let categoryNames = detection.categories.map { $0.categoryName ?? "?" }
                print("Detected categories: \(categoryNames)")
                
                if let category = detection.categories.first,
                   category.categoryName?.lowercased() == "book",
                   category.score > 0.4 {
                    print("Book detected (from delegate)! Confidence: \(category.score)")
                }
            }
        }
        
        func session(_ session: ARSession, didFailWithError error: Error) {
            let nsError = error as NSError
            print("ARSession failed: \(nsError.localizedDescription) (code: \(nsError.code))")

            let config = ARWorldTrackingConfiguration()
            config.environmentTexturing = .automatic
            config.planeDetection = [.horizontal]

            // Only restart if it's recoverable (code 200 = world tracking lost)
            if nsError.code == 200 {
                print("Restarting AR session due to world tracking failure")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.arView?.session.run(config, options: [.resetTracking, .removeExistingAnchors])
                }
            } else {
                print("Not restarting — unrecoverable sensor error")
            }
        }

        func sessionWasInterrupted(_ session: ARSession) {
            print("ARSession was interrupted")
        }

        func sessionInterruptionEnded(_ session: ARSession) {
            print("ARSession interruption ended — restarting")

            let config = ARWorldTrackingConfiguration()
            config.environmentTexturing = .automatic
            config.planeDetection = [.horizontal]
            arView?.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }
        
    }
}

extension AutoScreenshotARViewContainer.Coordinator: AVCaptureVideoDataOutputSampleBufferDelegate {
    // Called for every video frame
    func captureOutput(_ output: AVCaptureOutput,
                           didOutput sampleBuffer: CMSampleBuffer,
                           from connection: AVCaptureConnection) {
//        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
        guard let detector = objectDetector else { return }
        
        // Throttle detections to avoid overloading
        let now = Date().timeIntervalSince1970
        if now - lastDetectionTime < detectionInterval { return }
        lastDetectionTime = now

        let timestamp = Int(now * 1000)

        // Convert frame to MediaPipe MPImage
        guard let mpImage = try? MPImage(sampleBuffer: sampleBuffer, orientation: .up) else {
            print("Failed to create MPImage")
            return
        }

        // Asynchronously detect objects in this frame
        do {
            try detector.detectAsync(image: mpImage, timestampInMilliseconds: timestamp)
        } catch {
            print("Detection failed: \(error.localizedDescription)")
        }
    }
}
