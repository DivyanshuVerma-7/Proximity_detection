from yolo_wrapper import YoloDetector
from geometry import pixel_to_world
from distance import distance
from calibration import CameraCalibration
import cv2
import math

# --- Camera Calibration ---
img_w, img_h =  1280, 720        # Original video Resolution
f_mm = 16
sensor_w_mm = 23.5
sensor_h_mm = 15.6
camera_height = 2.35  # meters
pitch_deg = 77

# Create calibration object
calib = CameraCalibration(img_w, img_h, f_mm, sensor_w_mm, sensor_h_mm, camera_height, pitch_deg)

# Intrinsic parameters
fx, fy = calib.fx, calib.fy
cx_cam, cy_cam = calib.cx, calib.cy  # camera principal point

# Initialize YOLO
detector = YoloDetector("yolov8n.pt")  # or yolov8s.pt for better accuracy

# Video path
video_path = "/home/japneet/Documents/proximity-backend/project/data/videos/C0789.MP4"
cap = cv2.VideoCapture(video_path)

bbox_thickness = 12
frame_skip = 4
frame_id = 0

while cap.isOpened():
    ret, frame = cap.read()
    if not ret:
        break

    results = detector.model(frame, vid_stride=4)
    
    persons = []   # store (u_obj, v_obj, world_point)
    vehicles = []

    for r in results:
        for box in r.boxes:
            cls_id = int(box.cls[0])
            label = detector.model.names[cls_id]
            conf = float(box.conf[0])

            if label in detector.target_classes:
                x1, y1, x2, y2 = map(int, box.xyxy[0])
                # Bottom-center of detected object
                u_obj = int((x1 + x2) / 2)
                v_obj = y2

                # Convert to world coordinates
                world_pt = pixel_to_world(u_obj, v_obj, fx, fy, cx_cam, cy_cam, camera_height, math.radians(pitch_deg))

                if label == "person":
                    color = (0, 255, 0)
                    persons.append((u_obj, v_obj, world_pt))
                else:
                    color = (255, 0, 0)
                    vehicles.append((u_obj, v_obj, world_pt))

                # Draw bbox
                cv2.rectangle(frame, (x1, y1), (x2, y2), color, bbox_thickness)
                cv2.putText(frame, f"{label} {conf:.2f}", (x1, y1 - 10),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.9, color, 2)
                cv2.circle(frame, (u_obj, v_obj), 5, (0, 0, 255), -1)

    # Draw lines and distances
    for i, (u_p, v_p, world_p) in enumerate(persons):
        for j, (u_v, v_v, world_v) in enumerate(vehicles):
            if world_p is None or world_v is None:
                continue
            d = distance(world_p, world_v)

            # Draw line between person and vehicle
            cv2.line(frame, (u_p, v_p), (u_v, v_v), (0, 255, 255), 2)

            # Draw distance text at midpoint
            mid_x = int((u_p + u_v) / 2)
            mid_y = int((v_p + v_v) / 2)
            cv2.putText(frame, f"{d:.2f} m", (mid_x, mid_y - 10),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 255, 255), 2)

            print(f"Frame {frame_id}: Distance Person {i} - Vehicle {j} = {d:.2f} m")

    # Show frame
    cv2.namedWindow("YOLO Detection", 0)
    cv2.imshow("YOLO Detection", frame)

    if cv2.waitKey(30) & 0xFF == ord('q'):
        break

    frame_id += 1

cap.release()
cv2.destroyAllWindows()
print("Done!")
