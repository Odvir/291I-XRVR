//  AutoScreenshotContentView.swift
import SwiftUI
import RealityKit
import ARKit
import MediaPipeTasksVision
import UIKit
import CoreLocation
import Combine
import SwiftUI
import MapKit
struct AutoSavedBook: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let coordinate: CLLocationCoordinate2D
    var coverURL: URL? = nil
    let date = Date()
    static func == (lhs: AutoSavedBook, rhs: AutoSavedBook) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
struct AutoScreenshotContentView: View {
    @StateObject var wrapper = AutoCoordinatorWrapper()
    @State private var showLibrary  = false
    @State private var showMapSheet = false
    @AppStorage("ageRange")     var ageRange: String = ""
    @AppStorage("readingLevel") var readingLevel: String = ""
    @State private var showSurvey = true
    var body: some View {
        ZStack {
            // AR layer
            AutoScreenshotARViewContainer(wrapper: wrapper)
                .edgesIgnoringSafeArea(.all)
                .overlay(
                    ZStack {
                        VStack {
                            // ── TOP BAR ──────────────────────────────────────────────
                            HStack {
                                // 📚 Library (top-left)
                                Button(action: { showLibrary = true }) {
                                    Image(systemName: "books.vertical")
                                        .font(.system(size: 24))
                                        .padding(10)
                                        .background(Color.gray.opacity(0.4))
                                        .clipShape(Circle())
                                }
                                
                                Spacer()
                                
                                // 🗺️ Map (top-right)
                                Button(action: { showMapSheet = true }) {
                                    Image(systemName: "map")
                                        .font(.system(size: 24))
                                        .padding(10)
                                        .background(Color.gray.opacity(0.4))
                                        .clipShape(Circle())
                                }
                            }
                            .padding([.top, .horizontal], 20)
                            
                            Spacer()
                            
                            // ── BOTTOM BAR ───────────────────────────────────────────
                            ZStack {
                                // (no camera button in automatic mode)
                                
                                HStack {
                                    // ❌ Dismiss (left)
                                    if wrapper.bookVisible {
                                        Button(action: { wrapper.dismiss() }) {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 24))
                                                .foregroundColor(.black)
                                                .padding(12)
                                                .background(Color.gray.opacity(0.4))
                                                .clipShape(Circle())
                                        }
                                    } else {
                                        Spacer().frame(width: 60)
                                    }
                                    
                                    Spacer()
                                    
                                    // ❤️ Animate/Save (right)
                                    if wrapper.bookVisible {
                                        Button(action: {
                                            wrapper.saveLastBook()
                                            wrapper.bookVisible = false
                                            wrapper.animate()}){
                                            Image(systemName: "heart.fill")
                                                .font(.system(size: 28))
                                                .foregroundColor(.red)
                                                .padding(12)
                                                .background(Color.gray.opacity(0.4))
                                                .clipShape(Circle())
                                        }
                                    } else {
                                        Spacer().frame(width: 60)
                                    }
                                }
                                .padding(.horizontal, 30)
                            }
                            .padding(.bottom, 25)
                        }
                    }
                )
        }

        // ── SHEETS ─────────────────────────────────────────────────────
        .sheet(isPresented: $showLibrary) {
            VStack {
                Text("Saved Books")
                    .font(.title2)
                    .padding()

                List(wrapper.savedBooks) { book in
                    Text(book.title)
                }

                Button("Close") { showLibrary = false }
                    .padding()
            }
        }
        .sheet(isPresented: $showMapSheet) {
            AutoLibraryMapView(
                books: wrapper.savedBooks,
                isPresented: $showMapSheet
            )
        }
        .sheet(isPresented: $showSurvey) {
            VStack(spacing: 20) {
                Text("Tell us about you!")
                    .font(.title2).bold()
                    .padding(.top)

                // Age range
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

                // Reading level
                VStack(alignment: .leading) {
                    Text("How much do you read?")
                    Picker("Reading", selection: $readingLevel) {
                        Text("Rarely").tag("rarely")
                        Text("Often").tag("often")
                        Text("Avid").tag("avid")
                    }
                    .pickerStyle(.segmented)
                }

                Button("Continue") { showSurvey = false }
                    .disabled(ageRange.isEmpty || readingLevel.isEmpty)
                    .padding(.top)
            }
            .padding()
        }
    }
}

import CoreLocation
import Combine
final class AutoCoordinatorWrapper: NSObject, ObservableObject, CLLocationManagerDelegate {
    // AR-bridge (no displaySavedBook needed)
    weak var coordinator: AutoScreenshotARViewContainer.Coordinator?
    // Location
    private let locationManager = CLLocationManager()
    @Published private(set) var currentLocation: CLLocation?
    // Map & save state
    @Published var savedBooks: [AutoSavedBook] = []
    @Published var bookVisible = false
    // Title of last detection for the ❤️ button
    var lastBookTitle: String?
    // ─────────────────────────────────────────────────────────────
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func dismiss() {
            coordinator?.dismissBookAndInfo()  // clear AR entities
            bookVisible = false                // hide ❤️ / ❌
    }
    // CLLocation – patch dummy coords once we know real location
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        currentLocation = locs.last
        if let fix = currentLocation?.coordinate,
           let i   = savedBooks.lastIndex(where: { $0.coordinate.latitude == 0 && $0.coordinate.longitude == 0 }) {
            let old = savedBooks[i]
            savedBooks[i] = AutoSavedBook(title: old.title, coordinate: fix)
        }
    }
    // ─────────────────────────────────────────────────────────────
    // Called by ❤️ button
    func saveLastBook() {
        guard let title = lastBookTitle else { return }
        save(title: title)
        bookVisible = false
        coordinator?.clearTextAnchor()
    }
    func save(title: String, coverURL: URL? = nil) {
        let coord = currentLocation?.coordinate ?? .init(latitude: 0, longitude: 0)
        let entry = AutoSavedBook(title: title, coordinate: coord, coverURL: coverURL)
        guard !savedBooks.contains(where: { $0.title == title }) else { return }
        savedBooks.append(entry)
    }
    func animate() {
        coordinator?.animateBookToLibrary()
    }

}
struct AutoLibraryMapView: View {
    let books: [AutoSavedBook]
    @Binding var isPresented: Bool
    // 1. Group captures that share ≈ 11 m rounding
    private struct Cluster: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
        let books: [AutoSavedBook]
        var label: String {
            books.count == 1 ? books.first!.title
                             : "\(books.count) books"
        }
    }
    private var clusters: [Cluster] {
        func rounded(_ c: CLLocationCoordinate2D) -> (Double, Double) {
            let scale = 1_000.0          // ← was 10_000.0
            return ((c.latitude  * scale).rounded() / scale,
                    (c.longitude * scale).rounded() / scale)
        }
        let keyed = Dictionary(grouping: books) { b in
            let (lat, lon) = rounded(b.coordinate)
            return "\(lat),\(lon)"
        }
        return keyed.values.map { list in
            Cluster(coordinate: list.first!.coordinate, books: list)
        }
    }
    // 2. Start region (last capture or world view)
    private var startRegion: MKCoordinateRegion {
        if let last = books.last {
            return .init(center: last.coordinate,
                         span:   .init(latitudeDelta: 0.05, longitudeDelta: 0.05))
        } else {
            return .init(center: .init(latitude:   0, longitude:   0),
                         span:   .init(latitudeDelta: 80, longitudeDelta: 80))
        }
    }
    // 3. Local sheet state (list of titles when tapping a multi-pin)
    @State private var activeCluster: Cluster?
    var body: some View {
        VStack(spacing: 0) {
            // Full-screen map
            Map(coordinateRegion: .constant(startRegion),
                annotationItems: clusters) { cluster in
                MapAnnotation(coordinate: cluster.coordinate) {
                    VStack(spacing: 2) {
                        Image(systemName: "book.fill")
                            .resizable()
                            .frame(width: 24, height: 24)
                            .foregroundColor(.blue)
                        Text(cluster.label)
                            .font(.caption2)
                            .fixedSize()
                    }
                    .onTapGesture {
                        if cluster.books.count > 1 {
                            activeCluster = cluster
                        }
                    }
                }
            }
            .edgesIgnoringSafeArea(.top)
            // Bottom close button
            Button("Close") { isPresented = false }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray5))
                .foregroundColor(.blue)
        }
        // Sheet that lists books in a tapped cluster (optional)
        .sheet(item: $activeCluster) { cluster in
            VStack {
                Text("Books here").font(.headline).padding()
                List(cluster.books) { book in
                    Label(book.title, systemImage: "book")
                }
                Button("Close") { activeCluster = nil }
                    .padding()
            }
            .presentationDetents([.medium])
        }
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
        var bookTitle: String?
        var currentCoverURL: URL?
        var bookAnchor: AnchorEntity?
        init(wrapper: AutoCoordinatorWrapper) {
            self.wrapper = wrapper
        }
        
        var textAnchor: AnchorEntity?
        
        func dismissBookAndInfo() {
            if let anchor = textAnchor {
                arView?.scene.anchors.remove(anchor)
                textAnchor = nil
            }
            wrapper?.bookVisible = false
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
        func animateBookToLibrary() {
            guard let bookAnchor = self.bookAnchor else {
                print("No book anchor to animate.")
                return
            }
            let duration: TimeInterval = 2.0
            let moveDistance: Float = -0.5 // left on X-axis
            if let textAnchor = self.textAnchor {
                self.arView?.scene.anchors.remove(textAnchor)
            }
            for child in bookAnchor.children {
                let currentTransform = child.transform
                var newTransform = currentTransform
                newTransform.translation.x += moveDistance
                
                child.move(to: newTransform, relativeTo: nil, duration: duration, timingFunction: .easeInOut)
            }
            if let title = bookTitle {
                wrapper?.save(title: title, coverURL: currentCoverURL)
            } // <-- save it
            // Remove after animation finishes
            // Remove after animation finishes
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.5) {
                self.arView?.scene.anchors.remove(bookAnchor)
                self.bookAnchor = nil
                self.wrapper?.bookVisible = false // set hidden
            }
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
        
        func createFloatingCoverImage(from image: UIImage) -> Entity {
            guard let cgImage = image.cgImage else {
                print("❌ No CGImage found in UIImage")
                return ModelEntity()
            }
            // Convert UIImage into a RealityKit texture
            let texture: TextureResource
            do {
                texture = try TextureResource.generate(from: cgImage, options: .init(semantic: .color))
            } catch {
                print("❌ Failed to create texture: \(error)")
                return ModelEntity()
            }
            // Apply texture to a flat rectangular plane
            let width: Float = 0.14
            let height: Float = 0.2
            let mesh = MeshResource.generatePlane(width: width, height: height)
            var material = UnlitMaterial()
            material.baseColor = .texture(texture)
            let imageEntity = ModelEntity(mesh: mesh, materials: [material])
            // Position the image above the book
            imageEntity.position = [0, 0.02, 0.01]
            imageEntity.orientation = simd_quatf(angle: -.pi / 3.5, axis: [1, 0, 0])
            return imageEntity
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
                    self.sendImageToOpenAI(base64Image: base64) { title, summaryText in
                        self.bookTitle = title
                        self.fetchBookInfo(for: title) { infoText, coverURL in
                            DispatchQueue.main.async {
                                guard let arView = self.arView else { return }

                                let bookEntity = self.createBookWithTitle(title)
                                let cameraTransform = arView.cameraTransform
                                var position = cameraTransform.translation
                                position.z -= 0.4

                                let anchor = AnchorEntity(world: position)
                                anchor.addChild(bookEntity)

                                var titleEntity: Entity?
                                if let url = coverURL,
                                   let data = try? Data(contentsOf: url),
                                   let image = UIImage(data: data) {
                                    titleEntity = self.createFloatingCoverImage(from: image)
                                } else {
//                                    titleEntity = self.createFloatingTitle(text: title, for: bookEntity)
                                }

                                if let titleEntity = titleEntity {
                                    anchor.addChild(titleEntity)
                                }

                                arView.scene.anchors.append(anchor)
                                self.bookAnchor = anchor
                                self.currentCoverURL = coverURL
                                self.wrapper?.bookVisible = true

                                let fullText = "\(summaryText)\n\(infoText)"
//                                self.speakText(fullText)
                                self.displayTextInAR(fullText)
                            }
                        }
                    }
                }
            }
        }

        func fetchBookInfo(for title: String, completion: @escaping (String, URL?) -> Void) {
            let query = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let urlString = "https://www.googleapis.com/books/v1/volumes?q=intitle:\(query)&maxResults=1&printType=books"
            guard let url = URL(string: urlString) else {
                completion("No extra info available.", nil)
                return
            }
            URLSession.shared.dataTask(with: url) { data, response, error in
                if let error = error {
                    print("Books API error: \(error)")
                    completion("Rating unavailable.", nil)
                    return
                }
                guard let data = data else {
                    print("Books API returned no data.")
                    completion("Rating unavailable.", nil)
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
                        // NEW: Extract image URL if available
                        var imageURL: URL? = nil
                        if let imageLinks = volumeInfo["imageLinks"] as? [String: Any],
                           let thumbnail = imageLinks["thumbnail"] as? String {
                            // Replace HTTP with HTTPS if necessary
                            let secureURL = thumbnail.replacingOccurrences(of: "http://", with: "https://")
                            imageURL = URL(string: secureURL)
                            self.currentCoverURL = imageURL                        }
                        completion(info, imageURL)
                    } else {
                        completion("No extra info available.", nil)
                    }
                } catch {
                    print("Books API JSON error: \(error)")
                    completion("Rating unavailable.", nil)
                }
            }.resume()
        }
        func imageToBase64(image: UIImage) -> String? {
            guard let imageData = image.jpegData(compressionQuality: 0.8) else { return nil }
            return imageData.base64EncodedString()
        }

        func sendImageToOpenAI(base64Image: String, completion: @escaping (_ title: String, _ summary: String) -> Void) {
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
                            let summary = content.trimmingCharacters(in: .whitespacesAndNewlines)
                            self.wrapper?.lastBookTitle = title
                            self.wrapper?.bookVisible = true
                            completion(title, summary)
                        } else {
                            completion("Unknown Title", content)
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
            let anchor = AnchorEntity(world: [0, 0.4, -0.3])
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





