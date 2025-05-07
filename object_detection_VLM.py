# For object detection
import cv2
import mediapipe as mp
import time
from PIL import Image

# For VLM
from openai import OpenAI
from dotenv import load_dotenv
import os
import base64
import threading

# Keep track of last detection times for categories
last_detection_time = {}
snapshot_counter = 0   

# Set cooldown time (seconds)
COOLDOWN_PERIOD = 15

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
                    print(f"Detected BOOK with confidence {confidence:.2f}")
                    last_detection_time[label] = current_time
                    cv2.imwrite(f"snapshot_{snapshot_counter}.png", frame)
                    print(f"Saved snapshot_{snapshot_counter}.png")

                    # Run the OpenAI request in a separate thread to avoid blocking
                    filename = f"snapshot_{snapshot_counter}.png"
                    threading.Thread(target=pass_image_to_openai, args=(filename,)).start()
                    snapshot_counter += 1
                    
                else:
                    pass   # Suppress duplicate print

# Initialize object detector
options = ObjectDetectorOptions(
    base_options=BaseOptions(model_asset_path='object-detection/efficientdet_lite0.tflite'),
    score_threshold=0.5,
    running_mode=VisionRunningMode.LIVE_STREAM,
    result_callback=print_result  
)

# Function to send the image to OpenAI
def pass_image_to_openai(filename):

    # Load environment variables
    load_dotenv()
    openai_api_key = os.getenv("API_KEY")
    client = OpenAI(api_key=openai_api_key)

    # Read the image and encode it as base64
    with open(filename, "rb") as image_file:
        base64_image = base64.b64encode(image_file.read()).decode('utf-8')

    response = client.chat.completions.create(
        model="gpt-4o-mini", 
        messages=[
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "Describe the book in this image then write a poem about the book"},
                    {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{base64_image}"}}

                ]
            }
        ],
        max_tokens=200
    )
    print(response.choices[0].message.content)
    print("-------------------------")


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

        if cv2.waitKey(10) & 0xFF == 27:  # ESC key to exit
            break

cap.release() # Stop webcam
cv2.destroyAllWindows() # Close webcam window
