import cv2
import mediapipe as mp
import time

# Keep track of last detection times for categories
last_detection_time = {}
snapshot_counter = 0   

# Set cooldown time (seconds)
COOLDOWN_PERIOD = 60  # 60 seconds

# Load the object detector
BaseOptions = mp.tasks.BaseOptions
ObjectDetector = mp.tasks.vision.ObjectDetector
ObjectDetectorOptions = mp.tasks.vision.ObjectDetectorOptions
VisionRunningMode = mp.tasks.vision.RunningMode
# Callback function to receive results
def print_result(result, output_image, timestamp_ms):
    global last_detection_time
    global snapshot_counter

    if result.detections:
        for detection in result.detections:
            category = detection.categories[0]
            label = category.category_name
            confidence = category.score

            if label == "book" and confidence > 0.5:  # Optional: confidence threshold
                current_time = time.time()

                # Check if we've seen this category recently
                last_time = last_detection_time.get(label, 0)
                if current_time - last_time >= COOLDOWN_PERIOD:
                    print(f"📚 Detected BOOK with confidence {confidence:.2f}")
                    last_detection_time[label] = current_time
                    cv2.imwrite(f"snapshot_{snapshot_counter}.png", frame)
                    print(f"Saved snapshot_{snapshot_counter}.png")
                    snapshot_counter += 1
                else:
                    # Suppress duplicate print
                    pass
# Initialize object detector
options = ObjectDetectorOptions(
    base_options=BaseOptions(model_asset_path='object-detection/efficientdet_lite0.tflite'),
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
