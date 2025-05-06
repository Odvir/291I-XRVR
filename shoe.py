import cv2
import mediapipe as mp

mp_objectron = mp.solutions.objectron
mp_drawing = mp.solutions.drawing_utils

cap = cv2.VideoCapture(0)

with mp_objectron.Objectron(static_image_mode=False,
                            max_num_objects=5,
                            min_detection_confidence=0.5,
                            model_name='Shoe') as objectron:
    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break

        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = objectron.process(frame_rgb)

        if results.detected_objects:
            for detected_object in results.detected_objects:
                mp_drawing.draw_landmarks(
                    frame, detected_object.landmarks_2d, mp_objectron.BOX_CONNECTIONS)
                mp_drawing.draw_axis(
                    frame, detected_object.rotation, detected_object.translation)

        cv2.imshow('MediaPipe Objectron', frame)
        if cv2.waitKey(5) & 0xFF == 27:
            break

cap.release()
cv2.destroyAllWindows()
