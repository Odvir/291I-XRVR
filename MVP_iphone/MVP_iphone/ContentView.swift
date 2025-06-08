import SwiftUI
import RealityKit
import ARKit
import AVFoundation
import Vision

struct ContentView: View {
    @StateObject var wrapper = CoordinatorWrapper()
    @State private var showLibrary = false
    @State private var showFlash = false


    var body: some View {
        ZStack {
            ARViewContainer(wrapper: wrapper)
                .edgesIgnoringSafeArea(.all)
                .overlay(
                    VStack {
                        Spacer()
                        ZStack {
                            // 📸 Center Camera Button
                            Button(action: {
                                wrapper.coordinator?.takeSnapshotAndAddBook()
                            }) {
                                ZStack {
                                    Circle().fill(Color.gray.opacity(0.3)).frame(width: 60, height: 60)
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 26))
                                        .foregroundColor(.black)
                                }
                            }
                            
                            HStack {
                                // 📚 Bottom-left: Saved Library
                                Button(action: {
                                    showLibrary = true
                                }) {
                                    ZStack {
                                        Circle().fill(Color.gray.opacity(0.3)).frame(width: 50, height: 50)
                                        Image(systemName: "books.vertical")
                                            .font(.system(size: 22))
                                            .foregroundColor(.blue)
                                    }
                                }
                                
                                Spacer()
                                
                                // ❤️ Bottom-right: Heart button (only when visible)
                                if wrapper.bookVisible {
                                    Button(action: {
                                        wrapper.animate()
                                    }) {
                                        ZStack {
                                            Circle().fill(Color.gray.opacity(0.3)).frame(width: 50, height: 50)
                                            Image(systemName: "heart.fill")
                                                .font(.system(size: 24))
                                                .foregroundColor(.red)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 30)
                        }
                        .padding(.bottom, 20)
                    }
                )
            
                .sheet(isPresented: $showLibrary) {
                    VStack {
                        Text("Saved Books")
                            .font(.title2)
                            .padding()
                        
                        List(wrapper.savedBooks, id: \.self) { title in
                            Text(title)
                        }
                        
                        Button("Close") {
                            showLibrary = false
                        }
                        .padding()
                    }
                }
                .onChange(of: wrapper.flashToggle) { _ in
                    showFlash = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showFlash = false
                    }
                }
            
            if showFlash {
                    Color.black
                        .edgesIgnoringSafeArea(.all)
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.05), value: showFlash)
                }
        }
    }
}

class CoordinatorWrapper: ObservableObject {
    var coordinator: ARViewContainer.Coordinator?

    @Published var bookVisible: Bool = false
    @Published var savedBooks: [String] = []

    func animate() {
        coordinator?.animateBookToLibrary()
    }
    
    func save(title: String) {
            if !savedBooks.contains(title) {
                savedBooks.append(title)
            }
        }
    func takeSnapshot() {
            coordinator?.takeSnapshotAndAddBook()
        }
    func triggerFlash() {
        DispatchQueue.main.async {
            self.flashToggle.toggle()
        }
    }
    @Published var flashToggle = false
    
}



struct ARViewContainer: UIViewRepresentable {
    var wrapper: CoordinatorWrapper  // ✅ Add this

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(wrapper: wrapper)
        wrapper.coordinator = coordinator  // ✅ Link it
        return coordinator
    }
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Set up AR world tracking with plane detection
        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .automatic
        config.planeDetection = [.horizontal]
        arView.session.run(config)

        // Add a tap gesture recognizer to the AR view
//        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
//        arView.addGestureRecognizer(tapGesture)

        context.coordinator.arView = arView
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    class Coordinator: NSObject {
        weak var arView: ARView?
        var lastTapTime: Date = Date(timeIntervalSince1970: 0)
        let cooldownDuration: TimeInterval = 15 // seconds
        var textAnchor: AnchorEntity?
        var bookAnchor: AnchorEntity?
        var bookTitle: String?
        weak var wrapper: CoordinatorWrapper?

            init(wrapper: CoordinatorWrapper) {
                self.wrapper = wrapper
            }
        func takeSnapshotAndAddBook() {
            guard let arView = arView else { return }

            let now = Date()
            if now.timeIntervalSince(lastTapTime) < cooldownDuration {
                print("Cooldown active. Please wait...")
                return
            }
            lastTapTime = now

            arView.snapshot(saveToHDR: false) { optionalImage in
                guard let image = optionalImage else {
                    print("Snapshot failed.")
                    return
                }

                print("Snapshot taken.")
//                self.displayTextInAR("Snapshot captured.")
                self.wrapper?.triggerFlash()

                if let base64String = self.imageToBase64(image: image) {
                    self.sendImageToOpenAI(base64Image: base64String) { bookTitle in
                        guard let arView = self.arView else { return }
                        DispatchQueue.main.async {
                            let bookEntity = self.createBookWithTitle(bookTitle)
                            let titleEntity = self.createFloatingTitle(text: bookTitle, for: bookEntity)

                            let cameraTransform = arView.cameraTransform
                            var position = cameraTransform.translation
                            position.z -= 0.4
                            let anchor = AnchorEntity(world: position)

                            self.fetchBookInfo(for: bookTitle) { infoText in
                                DispatchQueue.main.async {
                                    let infoEntity = self.createFloatingInfo(text: infoText)
                                    infoEntity.position = [titleEntity.position.x,
                                                           titleEntity.position.y + 0.09,
                                                           titleEntity.position.z]
                                    anchor.addChild(infoEntity)
                                }
                            }

                            anchor.addChild(bookEntity)
                            anchor.addChild(titleEntity)
                            arView.scene.anchors.append(anchor)
                            self.bookAnchor = anchor
                            self.wrapper?.bookVisible = true
                        }
                    }
                } else {
                    print("Failed to encode image.")
                }
            }
        }

//
//        @objc func handleTap() {
//            guard let arView = arView else { return }
//
//            let now = Date()
//            if now.timeIntervalSince(lastTapTime) < cooldownDuration {
//                print("Cooldown active. Please wait...")
//                return
//            }
//            lastTapTime = now
//
//            arView.snapshot(saveToHDR: false) { optionalImage in
//                guard let image = optionalImage else {
//                    print("Snapshot failed.")
//                    return
//                }
//
//                print("Snapshot taken.")
//                self.displayTextInAR("Snapshot captured.")
//
//                if let base64String = self.imageToBase64(image: image) {
//                    self.sendImageToOpenAI(base64Image: base64String) { bookTitle in
//                        guard let arView = self.arView else { return }
//                        DispatchQueue.main.async {
//                            let bookEntity = self.createBookWithTitle(bookTitle)
//                            let titleEntity = self.createFloatingTitle(text: bookTitle, for: bookEntity)
//
//                            let cameraTransform = arView.cameraTransform
//                            var position = cameraTransform.translation
//                            position.z -= 0.4
//                            let anchor = AnchorEntity(world: position)
//                            self.fetchBookInfo(for: bookTitle) { infoText in
//                                DispatchQueue.main.async {
//                                    let infoEntity = self.createFloatingInfo(text: infoText)
//                                    infoEntity.position = [titleEntity.position.x,
//                                                           titleEntity.position.y + 0.09,
//                                                           titleEntity.position.z]
//                                    anchor.addChild(infoEntity)
//                                }
//                            }
//                            anchor.addChild(bookEntity)
//                            anchor.addChild(titleEntity)
//
//                            arView.scene.anchors.append(anchor)
//                            self.bookAnchor = anchor
//                            self.wrapper!.bookVisible = true// <-- Set visible
//
//                        }
//                    }
//                } else {
//                    print("Failed to encode image.")
//                }
//            }
//        }
        
        func animateBookToLibrary() {
            guard let bookAnchor = self.bookAnchor else {
                print("No book anchor to animate.")
                return
            }

            let duration: TimeInterval = 2.0
            let moveDistance: Float = -0.5 // left on X-axis

            for child in bookAnchor.children {
                let currentTransform = child.transform
                var newTransform = currentTransform
                newTransform.translation.x += moveDistance
                
                child.move(to: newTransform, relativeTo: nil, duration: duration, timingFunction: .easeInOut)
            }
            if let title = bookTitle {
                wrapper?.save(title: title)
            } // <-- save it
            // Remove after animation finishes
            // Remove after animation finishes
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.5) {
                self.arView?.scene.anchors.remove(bookAnchor)
                self.bookAnchor = nil
                self.wrapper?.bookVisible = false // set hidden
            }
        }


        func createFloatingTitle(text: String, for bookEntity: Entity) -> Entity {
            guard let model = bookEntity.components[ModelComponent.self] else {
                print("Book model missing")
                return ModelEntity()
            }

            let bounds = model.mesh.bounds
            let bookCenter = bounds.center
            let bookExtents = bounds.extents
            let coverZ = bookCenter.z + (bookExtents.z / 2)

            let textMesh = MeshResource.generateText(
                text,
                extrusionDepth: 0.001,
                font: .systemFont(ofSize: 0.01),
                containerFrame: CGRect(x: 0, y: 0, width: 0.1, height: 0.05),
                alignment: .center,
                lineBreakMode: .byWordWrapping
            )

            let material = UnlitMaterial(color: .white)
            let textEntity = ModelEntity(mesh: textMesh, materials: [material])

            let textCenter = textMesh.bounds.center
            textEntity.position = [
                -textCenter.x,
                 -textCenter.y,
                 0.06
            ]
            textEntity.orientation = simd_quatf(angle: -.pi / 8, axis: [1, 0, 0])
            return textEntity
        }

        func createFloatingInfo(text: String) -> Entity {
            let mesh = MeshResource.generateText(
                text,
                extrusionDepth: 0.001,
                font: .systemFont(ofSize: 0.01),
                containerFrame: CGRect(x: 0, y: 0, width: 0.1, height: 0.05),
                alignment: .center,
                lineBreakMode: .byWordWrapping
            )

            let material = UnlitMaterial(color: .white)
            let textEntity = ModelEntity(mesh: mesh, materials: [material])
            let center = mesh.bounds.center
            textEntity.position = [-center.x, -center.y, 0.06]
            textEntity.orientation = simd_quatf(angle: -.pi / 8, axis: [1, 0, 0])
            return textEntity
        }

        func createBookWithTitle(_ title: String) -> Entity {
            guard let arView = arView else  { return ModelEntity() }
            // Remove the previous book anchor if it exists
            if let oldAnchor = bookAnchor {
                arView.scene.anchors.remove(oldAnchor)
            }
            let bookEntity = try! Entity.loadModel(named: "Book")
            bookEntity.scale = [0.0007, 0.0007, 0.0007]
            bookEntity.orientation =
                simd_quatf(angle: .pi / 3, axis: [1, 0, 0]) *
                simd_quatf(angle: .pi / 2, axis: [0, 1, 0]) *
                simd_quatf(angle: -.pi / 8, axis: [0, 0, 1])
            return bookEntity
        }

        func fetchBookInfo(for title: String, completion: @escaping (String) -> Void) {
            let query = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let urlString = "https://www.googleapis.com/books/v1/volumes?q=intitle:\(query)&maxResults=1&printType=books"
            guard let url = URL(string: urlString) else {
                completion("No extra info available.")
                return
            }

            URLSession.shared.dataTask(with: url) { data, response, error in
                if let error = error {
                    print("Books API error: \(error)")
                    completion("Rating unavailable.")
                    return
                }
                guard let data = data else {
                    print("Books API returned no data.")
                    completion("Rating unavailable.")
                    return
                }
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let items = json["items"] as? [[String: Any]],
                       let first = items.first,
                       let volumeInfo = first["volumeInfo"] as? [String: Any] {

                        let avg = volumeInfo["averageRating"] as? Double
                        let count = volumeInfo["ratingsCount"] as? Int ?? 0
                        var info = ""
                        if let avg = avg {
                            info += String(format: "★ %.1f/5", avg)
                            if count > 0 { info += " (\(count) ratings)" }
                        } else {
                            info += "No rating found"
                        }
                        completion(info)
                    } else {
                        completion("No extra info available.")
                    }
                } catch {
                    print("Books API JSON error: \(error)")
                    completion("Rating unavailable.")
                }
            }.resume()
        }
        func detectBookCoverLocally(from originalImage: UIImage) {
            print("got called")
            guard let arView = arView else { return }
            guard let cgImage = originalImage.cgImage else {
                print("❌ Failed to get CGImage from snapshot")
                return
            }

            let request = VNDetectRectanglesRequest { request, error in
                if let error = error {
                    print("❌ Vision error: \(error)")
                    return
                }

                guard let results = request.results as? [VNRectangleObservation],
                      let best = results.first else {
                    print("❌ No rectangles found")
                    return
                }

                let width = CGFloat(cgImage.width)
                let height = CGFloat(cgImage.height)
                let box = best.boundingBox

                // Convert normalized bounding box to pixel space
                let rect = CGRect(
                    x: box.origin.x * width,
                    y: (1 - box.origin.y - box.height) * height,
                    width: box.width * width,
                    height: box.height * height
                )

                print("📐 Local bounding box: \(rect)")

                if let cropped = self.cropImage(originalImage, to: rect) {
                    DispatchQueue.main.async {
                        self.placeBookInAR(with: cropped)
                    }
                } else {
                    print("❌ Cropping failed.")
                }
            }

            // Tune rectangle detection
            request.minimumConfidence = 0.8
            request.minimumAspectRatio = 0.5
            request.maximumAspectRatio = 1.5

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }

        func placeBookInAR(with coverImage: UIImage) {
            guard let arView = arView else { return }
            // Remove the previous book anchor if it exists
            if let oldAnchor = bookAnchor {
                arView.scene.anchors.remove(oldAnchor)
            }

            // Create book dimensions (width, height, depth in meters)
            let bookWidth: Float = 0.12
            let bookHeight: Float = 0.02
            let bookDepth: Float = 0.18

            // Create the book mesh
            let bookMesh = MeshResource.generateBox(width: bookWidth, height: bookHeight, depth: bookDepth)

            // Create the texture from the cover image
            let textureResource: TextureResource
            do {
                textureResource = try TextureResource(
                    image: coverImage.cgImage!,
                    options: .init(semantic: .color)
                )
            } catch {
                print("Failed to create texture: \(error)")
                return
            }

            // Create material using the texture for the front (z+) face
            var bookMaterial = UnlitMaterial()
            bookMaterial.baseColor = MaterialColorParameter.texture(textureResource)

            // Apply same material to all sides for now (can be improved later)
            let materials: [RealityKit.Material] = Array(repeating: bookMaterial, count: 6)

            // Create entity with mesh and material
            let bookEntity = ModelEntity(mesh: bookMesh, materials: materials)

            // Place the book 0.4 meters in front of the camera
            let cameraTransform = arView.cameraTransform
            var position = cameraTransform.translation
            position.z -= 0.4
            let anchor = AnchorEntity(world: position)

            anchor.addChild(bookEntity)
            arView.scene.anchors.append(anchor)
            bookAnchor = anchor
        }

        func parseBoundingBox(from response: String) -> CGRect? {
            // Try to extract { "x":..., "y":..., ... } from response string
            if let data = response.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Int],
               let x = json["x"], let y = json["y"],
               let width = json["width"], let height = json["height"] {
                return CGRect(x: x, y: y, width: width, height: height)
            }
            return nil
        }

        func cropImage(_ image: UIImage, to rect: CGRect) -> UIImage? {
            guard let cgImage = image.cgImage else { return nil }
            guard let croppedCGImage = cgImage.cropping(to: rect) else { return nil }
            return UIImage(cgImage: croppedCGImage)
        }

        func findBookCoverRegion(from base64Image: String, originalImage: UIImage) {
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
                "model": "gpt-4o",
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            ["type": "text", "text": "Find only the front cover of the book in this image (ignore surroundings and spine) The cover should be around the center of the image and probably the largest rectangle in the image. Return the bounding box for said rectangle as four integers: x, y, width, height (in pixels). Format it exactly like this: {\"x\":123,\"y\":456,\"width\":789,\"height\":321}"],
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
                print("Failed to serialize JSON.")
                return
            }

            URLSession.shared.dataTask(with: request) { data, _, error in
                if let error = error {
                    print("OpenAI error: \(error)")
                    return
                }

                guard let data = data else {
                    print("No data received.")
                    return
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String,
                       let boundingBox = self.parseBoundingBox(from: content) {

                        print("📦 Bounding box: \(boundingBox)")

                        if let croppedImage = self.cropImage(originalImage, to: boundingBox) {
                            DispatchQueue.main.async {
                                self.placeBookInAR(with: croppedImage)
                            }
                        }

                    } else {
                        print("Could not parse bounding box from OpenAI response.")
                    }
                } catch {
                    print("JSON error: \(error)")
                }

            }.resume()
        }

        // Convert image to base64 string
        func imageToBase64(image: UIImage) -> String? {
            guard let imageData = image.jpegData(compressionQuality: 0.8) else { return nil }
            return imageData.base64EncodedString()
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

                        print("\n=== OpenAI Response ===\n\(content)\n========================\n")

                        // Extract title (everything before the first colon)
                        if let range = content.range(of: ":") {
                            let title = String(content[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                            completion(title)  // Call the completion handler with the title
                            self.bookTitle = title
                        } else {
                            completion("Unknown Title")
                        }

                        self.speakText(content)
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

        // MARK: - AVSpeech
        func speakText(_ text: String) {
            let synthesizer = AVSpeechSynthesizer()
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            synthesizer.speak(utterance)
        }

        // MARK: - Display helpers
        func displayTextInAR(_ text: String) {
            guard let arView = arView else { return }

            // Remove previous text anchor only
            if let oldAnchor = textAnchor {
                arView.scene.anchors.remove(oldAnchor)
            }

            let anchor = AnchorEntity(world: [0, 0.3, -0.5])  // Position text 0.5m in front of camera

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
            let boxMaterial = SimpleMaterial(color: .white.withAlphaComponent(0.5), isMetallic: false)
            let boxEntity = ModelEntity(mesh: boxMesh, materials: [boxMaterial])
            boxEntity.position = [0, 0, 0]

            boxEntity.addChild(textEntity)
            anchor.addChild(boxEntity)

            // Add new anchor and remember it
            arView.scene.addAnchor(anchor)
            textAnchor = anchor
        }
    }
}

#Preview {
    ContentView()
}
