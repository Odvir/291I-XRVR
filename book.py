import cv2
import torch

# Load YOLOv5 model
model = torch.hub.load('ultralytics/yolov5', 'yolov5s', pretrained=True)

# COCO class names (book is index 84)
BOOK_CLASS_ID = 84

# Open webcam
cap = cv2.VideoCapture(0)

while True:
    ret, frame = cap.read()
    if not ret:
        break

    # Run inference
    results = model(frame)

    # Parse detections
    for *box, conf, cls in results.xyxy[0]:
        if int(cls) == BOOK_CLASS_ID:
            x1, y1, x2, y2 = map(int, box)
            label = f'Book {conf:.2f}'
            cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
            cv2.putText(frame, label, (x1, y1 - 10),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)

    # Show frame
    cv2.imshow('Book Detection (YOLOv5)', frame)

    if cv2.waitKey(5) & 0xFF == 27:  # ESC key
        break

cap.release()
cv2.destroyAllWindows()
