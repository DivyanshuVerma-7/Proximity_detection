from ultralytics import YOLO

class YoloDetector:
    def __init__(self, model_path="yolov8l.pt"):
        # Load YOLOv8 model
        self.model = YOLO(model_path)
        # Define only the classes we want to detect
        self.target_classes = ["person", "car", "truck", "bus"]

    def detect(self, frame):
        results = self.model(frame,vid_stride= 4)  # Run detection
        detections = []

        for r in results:
            # Each r.boxes contains all detections in this frame
            for box in r.boxes:
                cls_id = int(box.cls[0])
                label = self.model.names[cls_id]

                if label in self.target_classes:
                    x1, y1, x2, y2 = map(int, box.xyxy[0])
                    # bottom-center point for distance calculation
                    cx = int((x1 + x2) / 2)
                    cy = y2
                    detections.append({
                        "label": label,
                        "bbox": (x1, y1, x2, y2),
                        "bottom_center": (cx, cy)
                    })
        return detections
