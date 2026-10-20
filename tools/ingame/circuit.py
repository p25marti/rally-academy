"""West Coast USA Off-Road Circuit (MAPS W5) for scripted drives: its road-network centre line (road nodes
dirttrack_1-32, read from map.getMap() on 0.39.4) resampled every metre, positions along it in metres from
dirttrack_1 in the circuit's direction, and course-frame lines for academy.course_run. The D05, D06 and E05
venues and gates were laid out from these positions (docs/MAPS.md, W5)."""
import math

NODES = [
    ['dirttrack_1', 566.92, 27.24], ['dirttrack_2', 567.63, 58.89], ['dirttrack_3', 575.91, 75.41],
    ['dirttrack_4', 591.26, 82.97], ['dirttrack_5', 606.78, 80.99], ['dirttrack_6', 620.08, 75.03],
    ['dirttrack_7', 641.09, 48.63], ['dirttrack_8', 659.19, 47.18], ['dirttrack_9', 683.03, 59.09],
    ['dirttrack_10', 699.14, 59.16], ['dirttrack_11', 710.99, 50.36], ['dirttrack_12', 738.55, 14.48],
    ['dirttrack_13', 752.79, 5.16], ['dirttrack_14', 768.04, 2.9], ['dirttrack_15', 780.55, 17.61],
    ['dirttrack_15a', 786.5, 39.22], ['dirttrack_15b', 789.4, 57.6], ['dirttrack_15c', 792.76, 75.75],
    ['dirttrack_16', 799.41, 112.31], ['dirttrack_17', 804.61, 148.51], ['dirttrack_18', 802.84, 173.38],
    ['dirttrack_19', 798.73, 186.52], ['dirttrack_19a', 784.01, 227.79], ['dirttrack_19b', 773.16, 236.32],
    ['dirttrack_19c', 755.72, 231.75], ['dirttrack_19d', 750.71, 218.19], ['dirttrack_20', 749.82, 175.64],
    ['dirttrack_21', 750.09, 147.42], ['dirttrack_22', 757.57, 127.78], ['dirttrack_23', 767.23, 106.64],
    ['dirttrack_23a', 768.78, 92.02], ['dirttrack_23b', 764.7, 76.35], ['dirttrack_23c', 752.41, 61.5],
    ['dirttrack_23d', 730.77, 42.19], ['dirttrack_23e', 716.25, 29.82], ['dirttrack_24', 693.8, 11.53],
    ['dirttrack_25', 680.09, -4.67], ['dirttrack_26', 671.63, -33.22], ['dirttrack_27', 666.75, -53.39],
    ['dirttrack_28', 654.37, -62.21], ['dirttrack_29', 585.2, -61.91], ['dirttrack_30', 570.82, -57.79],
    ['dirttrack_31', 566.96, -44.96], ['dirttrack_32', 567.25, -4.97], ['dirttrack_1', 566.92, 27.24],
]


def _resample():
    out = []
    for (na, ax, ay), (_, bx, by) in zip(NODES, NODES[1:]):
        seg = math.hypot(bx - ax, by - ay)
        for i in range(int(seg)):
            f = i / seg
            out.append((ax + (bx - ax) * f, ay + (by - ay) * f, na))
    return out


# (x, y, node the metre lies after), one per metre round the lap (about 1045).
SAMP = _resample()


def heading(i, span=4):
    a, b = SAMP[max(0, i - span)], SAMP[min(len(SAMP) - 1, i + span)]
    dx, dy = b[0] - a[0], b[1] - a[1]
    n = math.hypot(dx, dy)
    return dx / n, dy / n


def local(start, x, y):
    """World (x, y) -> course frame (x right, y ahead) of a start pose {pos, dir}."""
    fx, fy = start["dir"]["x"], start["dir"]["y"]
    n = math.hypot(fx, fy)
    fx, fy = fx / n, fy / n
    dx, dy = x - start["pos"]["x"], y - start["pos"]["y"]
    return round(dx * fy - dy * fx, 2), round(dx * fx + dy * fy, 2)


# The proving ground's copy of the circuit's first 640 m (road "circuit-hills", venues pg-circuit-*, ADR 0010) sits
# this far from the original, with the same heading.
PG_SHIFT = (-80.0, -455.0)


def line(start, a, b, step=1):
    """Course-frame points along the proving ground's copy of the centre line from metre a to b (every venue is on
    the proving ground since the stock-map venues went)."""
    dx, dy = PG_SHIFT
    return [local(start, SAMP[i][0] + dx, SAMP[i][1] + dy) for i in range(a, b, step)]
