//  AutoScreenshotContentView.swift

import SwiftUI
import RealityKit
import ARKit
import MediaPipeTasksVision
import UIKit

struct AutoScreenshotContentView: View {
    @StateObject var wrapper = AutoCoordinatorWrapper()
    @State private var showLibrary = false
    @AppStorage("ageRange") var ageRange: String = ""
    @AppStorage("readingLevel") var readingLevel: String = ""
    @State private var showSurvey = true

    var body: some View {
        ZStack {
            AutoScreenshotARViewContainer(wrapper: wrapper)

            VStack {
                Spacer()
                HStack {
                    // 📚 Bottom-left
                    Button(action: { showLibrary = true }) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 24))
                            .padding(10)
                            .background(Color.gray.opacity(0.4))
                            .clipShape(Circle())
                    }

                    Spacer()
                    
                        // ❌ Dismiss (left)
                        if wrapper.bookVisible {
                            Button(action: { wrapper.dismiss()}) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 24))
                                    .foregroundColor(.black)
                                    .padding(12)
                                    .background(Color.gray.opacity(0.4))
                                    .clipShape(Circle())
                            }
                        } else {
                            Spacer().frame(width: 60)   // reserve the same width when hidden
                        }

                        Spacer()

                    // ❤️ Bottom-right
                    if wrapper.bookVisible {
                        Button(action: {
                            wrapper.saveLastBook()
                            wrapper.bookVisible = false
                        }) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.red)
                                .padding(12)
                                .background(Color.gray.opacity(0.4))
                                .clipShape(Circle())
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showLibrary) {
            VStack {
                Text("Saved Books")
                    .font(.title2)
                    .padding()

                List(wrapper.savedBooks, id: \.self) { title in
                    Text(title)
                }

                Button("Close") { showLibrary = false }
                    .padding()
            }
        }
        .sheet(isPresented: $showSurvey) {
            VStack(spacing: 20) {
                Text("Tell us about you!")
                    .font(.title2)
                    .bold()
                    .padding(.top)

                // Age Range
                VStack(alignment: .leading) {
                    Text("What's your age range?")
                    Picker("Age", selection: $ageRange) {
                        Text("0–12").tag("0–12")
                        Text("12–24").tag("12–24")
                        Text("24–50").tag("24–50")
                        Text("50+").tag("50+")
                    }
                    .pickerStyle(.segmented)
                }

                // Reading Level
                VStack(alignment: .leading) {
                    Text("How much do you read?")
                    Picker("Reading", selection: $readingLevel) {
                        Text("Rarely").tag("rarely")
                        Text("Often").tag("often")
                        Text("Avid").tag("avid")
                    }
                    .pickerStyle(.segmented)
                }

                Button("Continue") {
                    showSurvey = false
                }
                .disabled(ageRange.isEmpty || readingLevel.isEmpty)
                .padding(.top)
            }
            .padding()
        }
    }
}
class AutoCoordinatorWrapper: ObservableObject {
    @Published var bookVisible: Bool = false
    @Published var savedBooks: [String] = []
    weak var coordinator: AutoScreenshotARViewContainer.Coordinator?
    var lastBookTitle: String? = nil
    func dismiss()        { coordinator?.dismissBookAndInfo()   }
    func saveLastBook() {
        if let title = lastBookTitle, !savedBooks.contains(title) {
            savedBooks.append(title)
        }
        coordinator?.clearTextAnchor() // <-- remove text when book is saved
    }
}
struct AutoScreenshotARViewContainer: UIViewRepresentable {
    var wrapper: AutoCoordinatorWrapper
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(wrapper: wrapper)
        wrapper.coordinator = coordinator
        return coordinator
    }
    

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .automatic
        config.planeDetection = [.horizontal]
        arView.session.run(config)

        arView.session.delegate = context.coordinator
        context.coordinator.arView = arView
        context.coordinator.setupObjectDetector()

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    class Coordinator: NSObject, ARSessionDelegate, ObjectDetectorLiveStreamDelegate {
        weak var arView: ARView?
        private var objectDetector: ObjectDetector?
        
        private var lastDetectionTime: TimeInterval = 0
        private let detectionInterval: TimeInterval = 1.0
        
        private var lastOpenAICallTime: TimeInterval = 0
        private let openAICooldown: TimeInterval = 10.0 // seconds
        weak var wrapper: AutoCoordinatorWrapper?

        init(wrapper: AutoCoordinatorWrapper) {
            self.wrapper = wrapper
        }
        
        var textAnchor: AnchorEntity?
        
        func dismissBookAndInfo() {

            if let textAnchor = self.textAnchor {
                arView?.scene.anchors.remove(textAnchor)
                self.textAnchor = nil
            }
            self.wrapper?.bookVisible = false
        }

        func setupObjectDetector() {
            do {
                let baseOptions = BaseOptions()
                baseOptions.modelAssetPath = "efficientdet_lite2.tflite"

                let options = ObjectDetectorOptions()
                options.baseOptions = baseOptions
                options.runningMode = .liveStream
                options.maxResults = 1
                options.scoreThreshold = 0.5
                options.objectDetectorLiveStreamDelegate = self

                objectDetector = try ObjectDetector(options: options)
                print("✅ MediaPipe ObjectDetector initialized")
            } catch {
                print("❌ Failed to initialize ObjectDetector: \(error)")
            }
        }
        func clearTextAnchor() {
                    guard let arView = arView, let anchor = textAnchor else { return }
                    arView.scene.anchors.remove(anchor)
                    self.textAnchor = nil
                }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            let now = Date().timeIntervalSince1970
            if now - lastDetectionTime < detectionInterval { return }
            lastDetectionTime = now

            let timestamp = Int(now * 1000)
            let pixelBuffer = frame.capturedImage
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()

            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                print("❌ Failed to create CGImage")
                return
            }

            let uiImage = UIImage(cgImage: cgImage)

            guard let mpImage = try? MPImage(uiImage: uiImage) else {
                print("❌ Failed to convert UIImage to MPImage")
                return
            }

            do {
                try objectDetector?.detectAsync(image: mpImage, timestampInMilliseconds: timestamp)
            } catch {
                print("❌ Detection failed: \(error.localizedDescription)")
            }
        }

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
                    print("📚 Book detected! Confidence: \(category.score)")
                    handleBookDetection()
                }
            }
        }

        func handleBookDetection() {
            guard let arView = arView else { return }
            let now = Date().timeIntervalSince1970
            if now - lastOpenAICallTime < openAICooldown {
                print("Skipping OpenAI call due to cooldown")
                return
            }
            lastOpenAICallTime = now

            arView.snapshot(saveToHDR: false) { image in
                guard let image = image else {
                    print("❌ Snapshot failed")
                    return
                }
                
                self.displayTextInAR("Book detected! Please wait...")

                if let base64 = self.imageToBase64(image: image) {
                    self.sendImageToOpenAI(base64Image: base64) { description in
                        DispatchQueue.main.async {
                            self.displayTextInAR(description)
                        }
                    }
                }
            }
        }

        func imageToBase64(image: UIImage) -> String? {
            guard let imageData = image.jpegData(compressionQuality: 0.8) else { return nil }
            return imageData.base64EncodedString()
        }

        func sendImageToOpenAI(base64Image: String, completion: @escaping (String) -> Void) {
            guard let apiKey = ProcessInfo.processInfo.environment["API_KEY"] else {
                print("API_KEY not found in environment variables.")
                return
            }

            let url = URL(string: "https://api.openai.com/v1/chat/completions")!
            var request = URLRequest(url: url)
            let age = UserDefaults.standard.string(forKey: "ageRange") ?? "unknown age"
            let reading = UserDefaults.standard.string(forKey: "readingLevel") ?? "unknown level"

            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "model": "gpt-4o-mini",
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            [
                                "type": "text",
                                "text": """
                                Identify the book in this image, then write a two-sentence description about it. The reader is in the age range \(age) and reads \(reading). Tailor your tone, language, and suggestions to suit this reader.

                                Respond in this format using line breaks:

                                [Book Title]: [Two-sentence description]

                                Vibe: [vibe]
                                Similar Books:
                                • [Book 1]
                                • [Book 2]
                                Example text:
                                The Lightning Thief: A modern-day hero discovers his power and embarks on a mythological quest.
                                Vibe: Whimsical
                                Similar Books:
                                • The Red Pyramid by Rick Riordan
                                • Aru Shah and the End of Time by Roshani Chokshi
                                """
                            ],
                            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                        ]
                    ]
                ],
                "max_tokens": 300
            ]

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                print("Failed to serialize JSON: \(error)")
                return
            }

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Error: \(error.localizedDescription)")
                    return
                }
                guard let data = data else { return }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let message = choices.first?["message"] as? [String: Any],
                       let content = message["content"] as? String {

                        print("\n=== OpenAI Response ===\n\(content)\n========================")

                        // Extract title (everything before the first colon)
                        if let range = content.range(of: ":") {
                            let title = String(content[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                            self.wrapper?.lastBookTitle = title
                            self.wrapper?.bookVisible = true
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
            }.resume()
        }

        func displayTextInAR(_ text: String) {
            guard let arView = arView else { return }
            
            if let oldAnchor = textAnchor {
                arView.scene.anchors.remove(oldAnchor) // remove old text
            }

            let anchor = AnchorEntity(world: [0, -0.15, -0.5])

            let textMesh = MeshResource.generateText(
                text,
                extrusionDepth: 0.004,
                font: .systemFont(ofSize: 0.015),
                containerFrame: CGRect(x: 0, y: 0, width: 0.25, height: 0.4),
                alignment: .center,
                lineBreakMode: .byWordWrapping
            )

            let textMaterial = SimpleMaterial(color: .black, isMetallic: false)
            let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
            let boundsCenter = textMesh.bounds.center
            textEntity.position = [-boundsCenter.x, -boundsCenter.y, 0]

            let boxMesh = MeshResource.generatePlane(width: textMesh.bounds.extents.x * 1.1, height: textMesh.bounds.extents.y * 1.5)
            var boxMaterial = SimpleMaterial()
            boxMaterial.color = .init(tint: .white.withAlphaComponent(0.6))
            let boxEntity = ModelEntity(mesh: boxMesh, materials: [boxMaterial])
            boxEntity.position = [0, 0, 0]

            boxEntity.addChild(textEntity)
            anchor.addChild(boxEntity)
            arView.scene.anchors.append(anchor)
            textAnchor = anchor
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            print("ARSession failed: \(error.localizedDescription)")
            let config = ARWorldTrackingConfiguration()
            config.environmentTexturing = .automatic
            config.planeDetection = [.horizontal]
            arView?.session.run(config, options: [.resetTracking, .removeExistingAnchors])
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
