import os
import cv2
import numpy as np
import asyncio
from asyncio import Lock
from ultralytics import YOLO
from typing import Dict, Any, List, Tuple
import time

# Config: update paths if needed
BASE_DIR = os.path.dirname(os.path.dirname(__file__))  # .. (backend)
DEFAULT_MODEL_PATH = os.path.join(BASE_DIR, "models", "yolov8n.pt")
DEFAULT_H_PATH = os.path.join(BASE_DIR, "homography_matrix789_img2world.npy")
DEFAULT_VIDEO_PATH = os.path.join(BASE_DIR, "video_data", "C0791.MP4")

# Lazy loaded
_MODEL = None
_H_IMG2WORLD = None


LATEST_RESULT: Dict[str, Any] = {"frames": [], "summary_zone": "green"}  # shared state
RESULT_LOCK = Lock()  # for thread-safe updates


def load_model(model_path: str = None) -> YOLO:
    global _MODEL
    if _MODEL is None:
        path = model_path or DEFAULT_MODEL_PATH
        if not os.path.exists(path):
            _MODEL = YOLO("yolov8n.pt")
        else:
            _MODEL = YOLO(path)
    return _MODEL

def load_homography(h_path: str = None) -> np.ndarray:
    global _H_IMG2WORLD
    if _H_IMG2WORLD is None:
        path = h_path or DEFAULT_H_PATH
        if not os.path.exists(path):
            raise FileNotFoundError(f"Homography file not found at {path}")
        _H_IMG2WORLD = np.load(path)
    return _H_IMG2WORLD

def process_and_calculate_distances(
    results,
    annotated_frame,
    H_img2world,
    scale_x,
    scale_y,
    proximity_threshold: float = 2.0,
    conf_threshold: float = 0.5
) -> Tuple[np.ndarray, List[Dict[str, Any]]]:
    detected_objects = []

    # Extract detections
    for r in results:
        if len(r.boxes) == 0:
            continue
        xyxy_arr = r.boxes.xyxy.cpu().numpy()
        conf_arr = r.boxes.conf.cpu().numpy()
        cls_arr = r.boxes.cls.cpu().numpy()
        names = r.names

        for i in range(len(xyxy_arr)):
            conf = float(conf_arr[i])
            if conf < conf_threshold:
                continue
            xyxy = xyxy_arr[i].tolist()
            class_id = int(cls_arr[i])
            class_name = names[class_id] if names is not None else str(class_id)

            x_pixel_resized = (xyxy[0] + xyxy[2]) / 2.0
            y_pixel_resized = xyxy[3]
            x_pixel_orig = x_pixel_resized * scale_x
            y_pixel_orig = y_pixel_resized * scale_y

            detected_objects.append({
                'class_name': class_name,
                'pixel_resized': (x_pixel_resized, y_pixel_resized),
                'pixel_orig': (x_pixel_orig, y_pixel_orig),
                'bbox_resized': [float(v) for v in xyxy],
                'confidence': conf
            })

    if not detected_objects:
        return annotated_frame, []

    # Transform to world coords
    pts = np.array([[[obj['pixel_orig'][0], obj['pixel_orig'][1]]] for obj in detected_objects], dtype=np.float32)
    pts_world = cv2.perspectiveTransform(pts, H_img2world).reshape(-1, 2)

    # Separate persons and cars
    persons = [(i, o) for i, o in enumerate(detected_objects) if o['class_name'].lower() == 'person']
    cars = [(i, o) for i, o in enumerate(detected_objects) if o['class_name'].lower() == 'car']

    if not persons or not cars:
        return annotated_frame, []

    # Build results: for each car, find nearest person
    summaries = []
    overall_zone = "green"
    for car_idx, car_obj in cars:
        car_world = pts_world[car_idx]

        # Find nearest person to this car
        nearest_p, nearest_dist = None, float("inf")
        for person_idx, person_obj in persons:
            person_world = pts_world[person_idx]
            dist = float(np.linalg.norm(person_world - car_world))
            if dist < nearest_dist:
                nearest_dist = dist
                nearest_p = (person_obj, person_world)

        # Zone classification with 3 levels
        if nearest_dist < proximity_threshold:
            zone, color, thickness = "red", (0, 0, 255), 2
            overall_zone = "red"
        elif nearest_dist < (proximity_threshold * 2):  # e.g. 2m–4m = yellow
            zone, color, thickness = "yellow", (0, 255, 255), 2
            if overall_zone != "red":
                overall_zone = "yellow"
        else:
            zone, color, thickness = "green", (0, 255, 0), 1
            if overall_zone not in ("red", "yellow"):
                overall_zone = "green"

        # Draw line
        p1_center = (int(nearest_p[0]['pixel_resized'][0]), int(nearest_p[0]['pixel_resized'][1]))
        p2_center = (int(car_obj['pixel_resized'][0]), int(car_obj['pixel_resized'][1]))
        cv2.line(annotated_frame, p1_center, p2_center, color, thickness)

        summaries.append({
            "car_world": {"x": float(car_world[0]), "y": float(car_world[1])},
            "distance_m": nearest_dist,
            "zone": zone,
            "nearest_person_world": {"x": float(nearest_p[1][0]), "y": float(nearest_p[1][1])}
        })

    return annotated_frame, summaries

try:
    to_thread = asyncio.to_thread
except AttributeError:
    async def to_thread(func, *args, **kwargs):
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, lambda: func(*args, **kwargs))

async def background_loop(video_path: str = None,
                          output_dims: Tuple[int,int] = (1280, 720),
                          proximity_threshold: float = 2.0,
                          conf_threshold: float = 0.5):
    """
    Run YOLO in background forever, looping video.
    Blocking operations are executed in threads using asyncio.to_thread
    so the FastAPI event loop remains responsive.
    """
    global LATEST_RESULT
    # load model & homography in a worker thread so startup doesn't block the loop
    model = await to_thread(load_model)
    H = await to_thread(load_homography)
    video = video_path or DEFAULT_VIDEO_PATH

    # open capture on main thread is okay, but we'll call .read() in a thread
    cap = cv2.VideoCapture(video)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video: {video}")

    orig_h, orig_w = None, None
    resized_w, resized_h = output_dims


    while True:
        # read frame (in thread)
        ret_frame = await to_thread(cap.read)
        ret, frame = ret_frame
        if not ret:
            # loop video: set to start (do in thread) and small sleep to avoid busy loop
            await to_thread(cap.set, cv2.CAP_PROP_POS_FRAMES, 0)
            await asyncio.sleep(0.05)
            continue

        if orig_h is None:
            orig_h, orig_w = frame.shape[:2]
            scale_x = orig_w / float(resized_w)
            scale_y = orig_h / float(resized_h)

        # resize in thread
        resized_frame = await to_thread(cv2.resize, frame, (resized_w, resized_h))

        # run model.predict in thread to avoid blocking event loop
        results = await to_thread(lambda: model.predict(source=resized_frame,
                                                        conf=conf_threshold,
                                                        classes=[0, 2],
                                                        verbose=False))

        annotated = resized_frame.copy()
        annotated, summary = process_and_calculate_distances(
            results, annotated, H, scale_x, scale_y,
            proximity_threshold, conf_threshold
        )

        cv2.imshow("Proximity Detection - Demo", annotated)
        cv2.waitKey(1)

        # compute overall_zone (same as before)
        if summary:
            zones = [s["zone"] for s in summary]
            if "red" in zones:
                overall_zone = "red"
            elif "yellow" in zones:
                overall_zone = "yellow"
            else:
                overall_zone = "green"
        else:
            overall_zone = "green"

        # thread-safe update
        async with RESULT_LOCK:
            # mutate rather than rebind (safer for any references)
            LATEST_RESULT.clear()
            LATEST_RESULT.update({
                "frames": [{"detections": summary}],
                "summary_zone": overall_zone
            })
