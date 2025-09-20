# intrinsics + rotation matrix + pixel to world
import math
import numpy as np

def pixel_to_world(u, v, fx, fy, cx, cy, h, theta):
    '''
    Convert pixel (u,v) -> (X,Z) world coordinates,
    fx, fy : Focal length (in pixels),
    cx, cy : prinicipal point (image centr),
    h: camera height above groun (in m),
    theta: camera tilt angle in radians

    '''
    xc = (u - cx) / fx
    yc = (v - cy) / fy
    zc = 1.0
    dc = np.array([xc, yc, zc])

    # Rotation about x-axis by tilt angle
    Rx = np.array([
        [1,0,0],
        [0, math.cos(theta), -math.sin(theta)],
        [0, math.sin(theta), math.cos(theta)]

    ])
    dw = Rx @ dc

    # intersect with ground plane Y = 0
    if dw[1] >=0:
        return None # ray doesn't hit ground in front
    s = -h/ dw[1]
    X = s * dw[0]
    Z = s * dw[2]
    return (X, Z)