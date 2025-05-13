import SwiftUI
import RealityKit
import ARKit
import AVFoundation

struct ContentView: View {
    var body: some View {
        ARViewContainer()
            .edgesIgnoringSafeArea(.all)
    }
}

struct ARViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .automatic
        config.planeDetection = [.horizontal]
        arView.session.run(config)

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        arView.addGestureRecognizer(tapGesture)

        context.coordinator.arView = arView
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }

    class Coordinator: NSObject {
        weak var arView: ARView?
        var lastTapTime: Date = Date(timeIntervalSince1970: 0)
        let cooldownDuration: TimeInterval = 15 // seconds

        @objc func handleTap() {
            guard let arView = arView else { return }

            let now = Date()
            if now.timeIntervalSince(lastTapTime) < cooldownDuration {
                print("⏳ Cooldown active. Please wait...")
                return
            }
            lastTapTime = now

            arView.snapshot(saveToHDR: false) { optionalImage in
                guard let image = optionalImage else {
                    print("❗ Snapshot failed.")
                    return
                }

                print("📸 Snapshot taken.")

                // Convert to base64 and send to OpenAI
                if let base64String = self.imageToBase64(image: image) {
                    self.sendImageToOpenAI(base64Image: base64String)
                } else {
                    print("Failed to encode image.")
                }
            }
        }

        func imageToBase64(image: UIImage) -> String? {
            guard let imageData = image.jpegData(compressionQuality: 0.8) else { return nil }
            return imageData.base64EncodedString()
        }

        func sendImageToOpenAI(base64Image: String) {
            guard let apiKey = ProcessInfo.processInfo.environment["API_KEY"] else {
                print("API_KEY not found in environment variables.")
                return
            }

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
                            ["type": "text", "text": "Identify the book in this image, then write a two-sentence description about it."],
                            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                        ]
                    ]
                ],
                "max_tokens": 100
            ]

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

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let message = choices.first?["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        print("\n=== OpenAI Response ===\n\(content)\n========================\n")

                        // Speak the response text
                        self.speakText(content)

                        // Update the AR overlay text
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

        func speakText(_ text: String) {
            let synthesizer = AVSpeechSynthesizer()
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            synthesizer.speak(utterance)
        }

        func displayTextInAR(_ text: String) {
            guard let arView = arView else { return }

            // Clear previous text anchors
            arView.scene.anchors.removeAll()

            let anchor = AnchorEntity(plane: .horizontal)

//            let mesh = MeshResource.generatePlane(width: 0.4, height: 0.2)
//            var material = SimpleMaterial()
//            material.color = .init(tint: .white.withAlphaComponent(0.9), texture: nil)
//
//            let planeEntity = ModelEntity(mesh: mesh, materials: [material])

            let textMesh = MeshResource.generateText(
                text,
                extrusionDepth: 0.002,
                font: .systemFont(ofSize: 0.04),
                containerFrame: CGRect(x: 0, y: 0, width: 0.4, height: 0.2),
                alignment: .center,
                lineBreakMode: .byWordWrapping
            )

            let textMaterial = SimpleMaterial(color: .black, isMetallic: false)
            let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])

            textEntity.position = [0, 0, 0.01] // Offset forward slightly

//            anchor.addChild(planeEntity)
            anchor.addChild(textEntity)

            arView.scene.addAnchor(anchor)
        }
    }
}

#Preview {
    ContentView()
}
