# calculate FOVh, FOVv

import math

class CameraCalibration:
    def __init__(self, img_w, img_h, f_mm, sensor_w_mm, sensor_h_mm, cam_h, pitch_deg):
        self.img_w = img_w
        self.img_h = img_h
        self.f_mm = f_mm
        self.sensor_w_mm = sensor_w_mm
        self.sensor_h_mm = sensor_h_mm
        self.cam_h = cam_h
        self.pitch = math.radians(pitch_deg)

        # Compute FOVs from focal length and sensor size
        self.FOVh = 2 * math.atan((sensor_w_mm /2)/f_mm)
        self.FOVv = 2 * math.atan((sensor_h_mm /2)/f_mm)

        # convert to focal lenth in pixels
        self.fx = (img_w / 2) / math.tan(self.FOVh / 2)
        self.fy = (img_h / 2) / math.tan(self.FOVv / 2)

        # Principal point
        self.cx = img_w / 2
        self.cy = img_h / 2

    