import cv2
import mediapipe as mp

# Load the object detector
BaseOptions = mp.tasks.BaseOptions
ObjectDetector = mp.tasks.vision.ObjectDetector
ObjectDetectorOptions = mp.tasks.vision.ObjectDetectorOptions
VisionRunningMode = mp.tasks.vision.RunningMode
# Callback function to receive results
def print_result(result, output_image, timestamp_ms):
    if result.detections:
        for detection in result.detections:
            category = detection.categories[0]
            if category.category_name == "book":
                print(f"📚 Detected BOOK with confidence {category.score:.2f}")

# Initialize object detector
options = ObjectDetectorOptions(
    base_options=BaseOptions(model_asset_path='efficientdet_lite0.tflite'),
    score_threshold=0.5,
    running_mode=VisionRunningMode.LIVE_STREAM,
    result_callback=print_result  # 👈 ADD THIS LINE
)


detector = ObjectDetector.create_from_options(options)


# Open webcam
cap = cv2.VideoCapture(0)

with detector:
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break

        # Convert the frame to RGB
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        # Send the frame to the detector
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame_rgb)
        detector.detect_async(mp_image, timestamp_ms=int(cv2.getTickCount() / cv2.getTickFrequency() * 1000))

        # Display the original frame
        cv2.imshow('MediaPipe Object Detection', frame)
        if cv2.waitKey(5) & 0xFF == 27:  # ESC key to exit
            break

cap.release()
cv2.destroyAllWindows()
