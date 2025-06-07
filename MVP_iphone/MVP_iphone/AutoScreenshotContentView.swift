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
        
        // For object detections
        private var lastDetectionTime: TimeInterval = 0
        private let detectionInterval: TimeInterval = 0.5
        
        // For snapshots
        var lastOpenAISnapshotTime: TimeInterval = 0
        let snapshotCooldown: TimeInterval = 15 // seconds
        
        // For display text to screen
        var textAnchor: AnchorEntity?

        // Set up object detector
        func setupObjectDetector() {
            do {
                let baseOptions = BaseOptions()
                baseOptions.modelAssetPath = "efficientdet_lite2.tflite"
                
                let options = ObjectDetectorOptions()
                options.baseOptions = baseOptions
                options.runningMode = .liveStream   // live camera feed mode
                options.maxResults = 1  // max num of objects to detect per frame
                options.scoreThreshold = 0.5    // min. confidence threshold
                
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
            
//            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_queue"))
//            captureSession.addOutput(output)
//
//            captureSession.startRunning() // run camera session async
//            print("Camera started")
            
            // Delay detection for 2 seconds to prevent immediate detections, handle in background thread
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.0) {
                output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_queue"))
                
                if captureSession.canAddOutput(output) {
                    captureSession.addOutput(output)
                }
                
                captureSession.startRunning()
                print("Camera started (after 2s delay)")
            }
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
            
//            print("Detection callback at: \(Date().timeIntervalSince1970)")

            for detection in result.detections {
                let categoryNames = detection.categories.map { $0.categoryName ?? "?" }
                print("Detected categories: \(categoryNames)")
                
                if let category = detection.categories.first,
                   category.categoryName?.lowercased() == "book",
                   category.score > 0.5 {
                    print("Book detected! Confidence: \(category.score)")
                    handleBookDetection() // call function to send snapshot to OpenAI
                }
//                else{
//                    print("No book in detection result (or low confidence)")
//                }
            }
        }
        
        func handleBookDetection() {
            guard let arView = arView else { return }

            let now = Date().timeIntervalSince1970
            if now - lastOpenAISnapshotTime < snapshotCooldown {
                print("Snapshot skipped.")
                return
            }
            lastOpenAISnapshotTime = now

            // Ensure ARKit is tracking
            guard let camera = arView.session.currentFrame?.camera else {
                print("No AR camera available")
                return
            }

            // Check if camera tracking before taking snapshot
            if case .notAvailable = camera.trackingState {
                print("AR tracking unavailable — skipping snapshot.")
                return
            }

            // Proceed with snapshot even if tracking is limited
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                arView.snapshot(saveToHDR: false) { image in
                    guard let image = image else {
                        print("Snapshot failed.")
                        return
                    }
                    
                    self.displayTextInAR("Snapshot captured.")
                    
                    // TEST: restart tracking and camera after snapshot taken
                    let config = ARWorldTrackingConfiguration()
                    config.environmentTexturing = .automatic
                    config.planeDetection = [.horizontal]
                    arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
                    
                    self.captureSession?.stopRunning()
                    self.captureSession = nil
                    self.startCameraCapture() // restart camera capture session
                    
                    DispatchQueue.global(qos: .utility).async {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil) // save snapshot to photo library
                        print("Snapshot saved to photo library")
                        
                        if let base64 = self.imageToBase64(image: image) {
                            self.sendImageToOpenAI(base64Image: base64) { description in
                                print("Detected Book Title: \(description)\n========================")
                            }
                        }
                    }
                }
            }
        }

        
        func sendImageToOpenAI(base64Image: String, completion: @escaping (String) -> Void) {
            guard let apiKey = ProcessInfo.processInfo.environment["API_KEY"] else {
                print("API_KEY not found in environment variables.")
                return
            }

            // OpenAI API request
            let url = URL(string: "https://api.openai.com/v1/chat/completions")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "model": "gpt-4o-mini",
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            ["type": "text", "text": "Identify the book in this image, then write a two-sentence description about it. Write it so that the book title goes first, then a colon, then the rest of the description. The book title should just be writtem like normal text"],
                            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                        ]
                    ]
                ],
                "max_tokens": 75
            ]

            // Send request to OpenAI API
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: body)
                request.httpBody = jsonData
            } catch {
                print("Failed to serialize JSON: \(error)")
                return
            }

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Error: \(error.localizedDescription)")
                    return
                }

                guard let data = data else {
                    print("No data received.")
                    return
                }

                // Process response from OpenAI
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let message = choices.first?["message"] as? [String: Any],
                       let content = message["content"] as? String {

                        print("\n=== OpenAI Response ===\n\(content)\n========================")

                        // Extract title (everything before the first colon)
                        if let range = content.range(of: ":") {
                            let title = String(content[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                            completion(title)  // Call the completion handler with the title
                        } else {
                            completion("Unknown Title")
                        }
                        
                        DispatchQueue.main.async {
                            self.displayTextInAR(content)
                        }
                    } else {
                        print("Could not parse OpenAI response.")
                        if let jsonString = String(data: data, encoding: .utf8) {
                            print("Response JSON: \(jsonString)")
                        }
                    }
                } catch {
                    print("JSON parsing error: \(error)")
                }
            }

            task.resume()
        }
        
        // Convert image to base64 string
        func imageToBase64(image: UIImage) -> String? {
            guard let imageData = image.jpegData(compressionQuality: 0.8) else { return nil }
            return imageData.base64EncodedString()
        }
        
        func displayTextInAR(_ text: String) {
            guard let arView = arView else { return }

            // Remove previous text anchor only
            if let oldAnchor = textAnchor {
                arView.scene.anchors.remove(oldAnchor)
            }

            let anchor = AnchorEntity(world: [0, 0, -0.5])  // Position text 0.5m in front of camera

            let textMesh = MeshResource.generateText(
                text,
                extrusionDepth: 0.004,
                font: .systemFont(ofSize: 0.01),
                containerFrame: CGRect(x: 0, y: 0, width: 0.25, height: 0.4),
                alignment: .center,
                lineBreakMode: .byWordWrapping
            )

            let textMaterial = SimpleMaterial(color: .black, isMetallic: false)
            let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])

            let boundsCenter = textMesh.bounds.center
            textEntity.position = [-boundsCenter.x, -boundsCenter.y, 0]

            let textSize = textMesh.bounds.extents
            let boxMesh = MeshResource.generatePlane(width: textSize.x * 1.1, height: textSize.y * 1.5)
            var boxMaterial = SimpleMaterial()
            boxMaterial.color = .init(tint: .black.withAlphaComponent(0.5))
            let boxEntity = ModelEntity(mesh: boxMesh, materials: [boxMaterial])
            boxEntity.position = [0, 0, 0]

            boxEntity.addChild(textEntity)
            anchor.addChild(boxEntity)

            // Add new anchor and remember it
            arView.scene.addAnchor(anchor)
            textAnchor = anchor
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
                    
                    // TEST: restart camera capture?
//                    self.captureSession?.stopRunning()
//                    self.captureSession = nil
//                    self.startCameraCapture()
                }
            } else {
                print("Not restarting — unrecoverable sensor error")
            }
        }

//        func sessionWasInterrupted(_ session: ARSession) {
//            print("ARSession was interrupted")
//        }

        func sessionInterruptionEnded(_ session: ARSession) {
            // Invoked when you toggle out of iOS app
            print("ARSession interruption ended — restarting")

            // reset AR tracking
            let config = ARWorldTrackingConfiguration()
            config.environmentTexturing = .automatic
            config.planeDetection = [.horizontal]
            arView?.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            
            // TEST
            self.captureSession?.stopRunning()
            self.captureSession = nil
            startCameraCapture() // restart camera capture session
        }
        
    }
}

extension AutoScreenshotARViewContainer.Coordinator: AVCaptureVideoDataOutputSampleBufferDelegate {
    // Called for every video frame
    func captureOutput(_ output: AVCaptureOutput,
                           didOutput sampleBuffer: CMSampleBuffer,
                           from connection: AVCaptureConnection) {
        guard let detector = objectDetector else { return }
        
        // Throttle detections to avoid overloading
        let now = Date().timeIntervalSince1970
//        print("Frame received at: \(now)")
        if now - lastDetectionTime < detectionInterval {
//            print("Skipping frame due to throttle")
            return
        }
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
