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

# For TTS
from gtts import gTTS
import playsound

# For text display
import textwrap 

# Keep track of last detection times for categories
last_detection_time = {}
snapshot_counter = 0   
response_text = ""
response_text_time = 0
TEXT_DISPLAY_DURATION = 45

# Set cooldown time (seconds)
COOLDOWN_PERIOD = 15

# Config
RESIZE_IMAGES = False  # Set to False to disable image resizing
RESIZED_WIDTH = 1024
RESIZED_HEIGHT = 576

# Load the object detector
BaseOptions = mp.tasks.BaseOptions
ObjectDetector = mp.tasks.vision.ObjectDetector
ObjectDetectorOptions = mp.tasks.vision.ObjectDetectorOptions
VisionRunningMode = mp.tasks.vision.RunningMode

# Callback function to receive results
def print_result(result, output_image, timestamp_ms):
    global last_detection_time
    global snapshot_counter
    global response_text
    global response_text_time

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
    global response_text
    global response_text_time
    
    # Load environment variables
    load_dotenv()
    openai_api_key = os.getenv("API_KEY")
    client = OpenAI(api_key=openai_api_key)

    if RESIZE_IMAGES:
        img = cv2.imread(filename)
        resized = cv2.resize(img, (RESIZED_WIDTH, RESIZED_HEIGHT))
        cv2.imwrite(filename, resized)
        print(f"Image resized to {RESIZED_WIDTH}x{RESIZED_HEIGHT}")

    # Read the image and encode it as base64
    with open(filename, "rb") as image_file:
        base64_image = base64.b64encode(image_file.read()).decode('utf-8')

    response = client.chat.completions.create(
        model="gpt-4o-mini", 
        messages=[
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "Identify the book in this image then write a one sentence description about it"},
                    {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{base64_image}"}}

                ]
            }
        ],
        max_tokens=100
    )

    response_text = response.choices[0].message.content
    response_text_time = time.time()

    # Convert to speech
    tts = gTTS(text=response_text, lang='en')
    mp3_filename = f"{filename}_description.mp3"
    tts.save(mp3_filename)

    # Play the audio
    playsound.playsound(mp3_filename)


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

        # Check if the text should still be displayed
        current_time = time.time()
        if current_time - response_text_time > TEXT_DISPLAY_DURATION:
            response_text = ""  # Clear the text after 30 seconds

        # Overlay the response text on the frame
        if response_text:
            wrapped_text = textwrap.wrap(response_text, width=40)

            x = 20
            y = 40
            line_height = 25  # Height of each line of text
            padding = 15      # Padding around the text
            max_line_width = max([cv2.getTextSize(line, cv2.FONT_HERSHEY_SIMPLEX, 0.7, 2)[0][0] for line in wrapped_text])

            box_x1 = x - padding
            box_y1 = y - padding - 15
            box_x2 = x + max_line_width + padding
            box_y2 = y + len(wrapped_text) * line_height + padding // 2 - 10

            # Draw white rectangle behind text
            cv2.rectangle(frame, (box_x1, box_y1), (box_x2, box_y2), (255, 255, 255), -1)

            # Draw each line of text on the frame
            for i, line in enumerate(wrapped_text):
                y_offset = y + i * line_height  # Adjust y-coordinate for each line
                cv2.putText(frame, line, (x, y_offset), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0,0,0), 2)
                

        # Display the original frame
        cv2.imshow('MediaPipe Object Detection', frame)

        if cv2.waitKey(10) & 0xFF == 27:  # ESC key to exit
            break

cap.release() # Stop webcam
cv2.destroyAllWindows() # Close webcam window
