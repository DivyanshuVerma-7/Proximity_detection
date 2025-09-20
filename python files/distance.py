import math

def distance(p1, p2):
    """
    point si (X, Z)
    """
    if p1 is None or p2 is None:
        return None
    X1, Z1 = p1
    X2, Z2 = p2
    return math.sqrt((X1 - X2)**2 + (Z1 - Z2)**2)