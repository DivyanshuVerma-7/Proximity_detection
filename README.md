# Proximity_detection
## Requirements  
Python 3.9+
Flutter SDK (latest stable)
A device (laptop/phone) connected to the same Wi-Fi for mobile testing
Backend (FastAPI + YOLOv8)
## 1. Clone the repository  
git clone [https://github.com/your-username/proximity-detection.git](https://github.com/your-username/proximity-detection.git)
cd proximity-detection/backend

## 2. Create & activate virtual environment  
python -m venv .venv
source .venv/bin/activate    # Linux / Mac
.venv\Scripts\activate      # Windows PowerShell

## 3. Install dependencies  
pip install -r requirements.txt

## 4. Place your model and video  
Model: backend/models/yolov8n.pt
Video: backend/video_data/C0791.MP4
Homography matrix: backend/homography_matrix789_img2world.npy

## 5. Run the backend
uvicorn backend.app:app --host 0.0.0.0 --port 8000 --reload

API Health check: http://localhost:8000/health
Results (JSON): http://localhost:8000/results
WebSocket: ws://<your-ip>:8000/ws/results
If testing on a mobile device, replace localhost with your machine’s LAN IP (e.g. 192.168.x.x).
## Frontend (Flutter App)
## 1. Move into frontend folder
cd ../frontend

## 2. Get Flutter dependencies
flutter pub get

## 3. Run the app
For web (Chrome):
flutter run -d chrome


## For mobile (Android/iOS):
flutter run

## 4. Connect to backend
In the app, open the settings (gear icon)
Enter your backend host: 192.168.x.x:8000
Save → the app will auto-connect via WebSocket and start showing live updates.
In the app, open the settings (gear icon)
Enter your backend host: 192.168.x.x:8000
Save → the app will auto-connect via WebSocket and start showing live updates.
