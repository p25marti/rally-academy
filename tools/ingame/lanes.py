"""Gravel lane DR825 west of the town (MAPS W6) for scripted drives: its road-network nodes (map.getMap() on 0.39.4),
resampled every metre in either direction, as course-frame lines for academy.course_run. The D03 and D04 venues and
gates were laid out from these positions."""
import math

import circuit

DR825 = [
    ['DR825_2', -867.16, -64.41], ['DR825_3', -859.71, -68.47], ['DR825_4', -851.45, -70.65], ['DR825_5', -822.97, -69.45],
    ['DR825_6', -813.73, -71.62], ['DR825_7', -806.42, -76.17], ['DR825_8', -801.14, -82.66], ['DR825_9', -798.41, -91.99],
    ['DR825_10', -799.83, -101.05], ['DR825_11', -805.6, -108.67], ['DR825_12', -813.29, -114.03],
    ['DR825_13', -824.36, -123.64], ['DR825_14', -827.73, -130.8], ['DR825_15', -827.73, -139.21],
    ['DR825_16', -824.05, -151.56], ['DR825_17', -821.76, -162.82],
]


# The proving ground's copy of the lane (road "gravel-lane", venues pg-lane-*) sits this far from the original.
PG_SHIFT = (900.0, 200.0)


def samples(first, last, shift=(0.0, 0.0)):
    """(x, y) every metre from node DR825_<first> to DR825_<last> (either direction), moved by `shift`."""
    ids = [int(n.split('_')[1]) for n, _, _ in DR825]
    sel = [p for p, i in zip(DR825, ids) if min(first, last) <= i <= max(first, last)]
    if first > last:
        sel = sel[::-1]
    out = []
    for (_, ax, ay), (_, bx, by) in zip(sel, sel[1:]):
        seg = math.hypot(bx - ax, by - ay)
        out += [(ax + (bx - ax) * i / seg + shift[0], ay + (by - ay) * i / seg + shift[1]) for i in range(int(seg))]
    return out


def line(start, first, last, a, b):
    """Course-frame points (circuit.local) from metre a to b of the proving ground's copy of the lane between those
    nodes (every venue is on the proving ground since the stock-map venues went)."""
    return [circuit.local(start, x, y) for x, y in samples(first, last, PG_SHIFT)[a:b]]
