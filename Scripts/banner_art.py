"""Generate 4K & 8K Japanese mandala, mathematical mosaic, hyperbolic grid,
Seigaiha waves, Sumi-e ink, and botanical sketch atlases for NotchBanner.
Requires Python 3 + librsvg (rsvg-convert).
"""
import argparse
from math import atan2, cos, exp, pi, sin, sqrt
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent / "Resources"
TAU = 2.0 * pi


def path_str(pts, closed=False):
    if not pts:
        return ""
    d = " ".join(("M" if i == 0 else "L") + f"{x:.2f},{y:.2f}" for i, (x, y) in enumerate(pts))
    return d + (" Z" if closed else "")


def stroke_path(pts, width=2.4, opacity=0.95, closed=False, dash=None):
    if not pts:
        return ""
    d = path_str(pts, closed=closed)
    da = f' stroke-dasharray="{dash}"' if dash else ""
    return (
        f'<path d="{d}" stroke="white" stroke-width="{width:.2f}" opacity="{opacity:.2f}" '
        f'fill="none" stroke-linecap="round" stroke-linejoin="round"{da}/>'
    )


def fill_path(pts, opacity=0.90):
    if not pts:
        return ""
    return f'<path d="{path_str(pts, closed=True)}" fill="white" opacity="{opacity:.2f}"/>'


def circle(cx, cy, r, width=2.0, opacity=0.92, fill=False, dash=None):
    if fill:
        return f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{r:.2f}" fill="white" opacity="{opacity:.2f}"/>'
    da = f' stroke-dasharray="{dash}"' if dash else ""
    return (
        f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{r:.2f}" stroke="white" stroke-width="{width:.2f}" '
        f'opacity="{opacity:.2f}" fill="none"{da}/>'
    )


def curve(fn, a=0.0, b=TAU, n=120, **kw):
    return stroke_path([fn(a + (b - a) * i / n) for i in range(n + 1)], **kw)


def tapered_stroke(pts, widths, opacity=0.92):
    """Variable-width calligraphic brush stroke as a closed filled ribbon."""
    if len(pts) < 2:
        return ""
    left, right = [], []
    n = len(pts)
    for i, (x, y) in enumerate(pts):
        if i == 0:
            dx, dy = pts[1][0] - x, pts[1][1] - y
        elif i == n - 1:
            dx, dy = x - pts[i - 1][0], y - pts[i - 1][1]
        else:
            dx, dy = pts[i + 1][0] - pts[i - 1][0], pts[i + 1][1] - pts[i - 1][1]
        mag = max(1e-6, sqrt(dx * dx + dy * dy))
        nx, ny = -dy / mag, dx / mag
        w = widths[i] * 0.5
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    poly = left + list(reversed(right))
    return fill_path(poly, opacity=opacity)


# ---------------------------------------------------------------------------
# Plate 0: Japanese Sacred Mandala (Lotus, Kiku Chrysanthemum, Asanoha ring)
# Coordinates centered at (0, 0), radius ~215 inside a 500x500 tile
# ---------------------------------------------------------------------------
def build_japanese_mandala():
    out = []

    # Outer sacred boundary rings + cardinal finials
    for r, w, op in [(216, 2.2, 0.92), (208, 1.1, 0.72), (194, 1.8, 0.88), (156, 1.8, 0.86),
                     (150, 1.0, 0.65), (112, 1.6, 0.85), (72, 1.6, 0.88), (36, 1.4, 0.85)]:
        out.append(circle(0, 0, r, width=w, opacity=op))

    # 32-fold fine pearl bead ring between r=194 and r=208
    for i in range(64):
        th = i * TAU / 64.0
        r_dot = 201.0
        out.append(circle(r_dot * cos(th), r_dot * sin(th), 1.8 if i % 2 == 0 else 1.1, opacity=0.82, fill=True))

    # Outer 16-fold stylized lotus petals (r = 156 .. 194)
    for i in range(16):
        base = i * TAU / 16.0
        half = TAU / 32.0 * 0.92
        pts_outer = []
        pts_inner = []
        for s in range(25):
            t = s / 24.0
            ang = base - half + 2 * half * t
            arch = sin(t * pi)
            tip = pow(arch, 0.55)
            r = 156.0 + 38.0 * tip + 6.0 * pow(arch, 4.0)
            pts_outer.append((r * cos(ang), r * sin(ang)))
            r2 = 158.0 + 28.0 * tip
            pts_inner.append((r2 * cos(ang), r2 * sin(ang)))
        out.append(stroke_path(pts_outer, width=1.9, opacity=0.94))
        out.append(stroke_path(pts_inner, width=1.1, opacity=0.72))
        # Center vein + jewel dot
        out.append(stroke_path([(158 * cos(base), 158 * sin(base)), (185 * cos(base), 185 * sin(base))], width=1.0, opacity=0.68))
        out.append(circle(172 * cos(base), 172 * sin(base), 2.3, opacity=0.88, fill=True))

    # Middle 16-fold overlapping Asanoha / Star-Diamond band (r = 112 .. 150)
    for i in range(16):
        a0 = i * TAU / 16.0
        a1 = (i + 0.5) * TAU / 16.0
        a2 = (i + 1.0) * TAU / 16.0
        p_in0 = (112 * cos(a0), 112 * sin(a0))
        p_in2 = (112 * cos(a2), 112 * sin(a2))
        p_mid = (131 * cos(a1), 131 * sin(a1))
        p_out = (150 * cos(a1), 150 * sin(a1))
        p_out0 = (150 * cos(a0), 150 * sin(a0))
        out.append(stroke_path([p_in0, p_out, p_in2], width=1.55, opacity=0.88))
        out.append(stroke_path([p_out0, p_mid, p_out], width=1.05, opacity=0.62))
        out.append(stroke_path([p_in0, p_mid, p_in2], width=1.05, opacity=0.62))
        out.append(stroke_path([(112 * cos(a1), 112 * sin(a1)), p_out], width=1.0, opacity=0.65))
        out.append(circle(p_mid[0], p_mid[1], 1.8, opacity=0.85, fill=True))

    # Inner 8-fold Grand Lotus Petals (r = 72 .. 112) + secondary offset 8-fold petals
    for layer, offset, rad_hi, w, op in [(0, 0.0, 112.0, 2.0, 0.96), (1, TAU / 16.0, 106.0, 1.35, 0.78)]:
        for i in range(8):
            base = i * TAU / 8.0 + offset
            half = TAU / 16.0 * 0.88
            pts = []
            for s in range(29):
                t = s / 28.0
                ang = base - half + 2 * half * t
                arch = sin(t * pi)
                r = 72.0 + (rad_hi - 72.0) * (0.75 * pow(arch, 0.65) + 0.25 * pow(arch, 3.0))
                pts.append((r * cos(ang), r * sin(ang)))
            out.append(stroke_path(pts, width=w, opacity=op))
            if layer == 0:
                # Inner filigree flame curve
                pts2 = []
                for s in range(21):
                    t = s / 20.0
                    ang = base - half * 0.58 + half * 1.16 * t
                    arch = sin(t * pi)
                    r = 75.0 + 25.0 * pow(arch, 0.75)
                    pts2.append((r * cos(ang), r * sin(ang)))
                out.append(stroke_path(pts2, width=1.1, opacity=0.72))
                out.append(circle(90 * cos(base), 90 * sin(base), 2.5, opacity=0.90, fill=True))

    # Kiku (16-petal Imperial Chrysanthemum) core (r = 36 .. 72)
    for i in range(16):
        a = i * TAU / 16.0
        half = TAU / 32.0 * 0.78
        pts = []
        for s in range(17):
            t = s / 16.0
            ang = a - half + 2 * half * t
            r = 36.0 + 35.0 * pow(sin(t * pi), 0.45)
            pts.append((r * cos(ang), r * sin(ang)))
        out.append(stroke_path(pts, width=1.65, opacity=0.92))
        out.append(stroke_path([(38 * cos(a), 38 * sin(a)), (65 * cos(a), 65 * sin(a))], width=0.95, opacity=0.58))

    # Central sacred geometry: dual nested octagram + radiant lotus heart
    for rot, r, w in [(0.0, 35.0, 1.45), (pi / 8.0, 35.0, 1.15)]:
        sq = [(r * cos(rot + k * pi / 2), r * sin(rot + k * pi / 2)) for k in range(4)]
        out.append(stroke_path(sq, width=w, opacity=0.88, closed=True))
    for i in range(16):
        a = i * TAU / 16.0
        out.append(circle(22 * cos(a), 22 * sin(a), 1.5, opacity=0.85, fill=True))
    out.append(circle(0, 0, 15.0, width=1.8, opacity=0.95))
    out.append(circle(0, 0, 7.5, width=1.3, opacity=0.85))
    out.append(circle(0, 0, 3.2, opacity=0.96, fill=True))

    # Cardinal 8-way decorative lotus finials extending gracefully outside r=216
    for i in range(8):
        a = i * TAU / 8.0
        ca, sa = cos(a), sin(a)
        nx, ny = -sa, ca
        tip_len = 236.0 if i % 2 == 0 else 228.0
        w_base = 11.0 if i % 2 == 0 else 7.5
        p1 = (216 * ca - w_base * nx, 216 * sa - w_base * ny)
        p2 = (tip_len * ca, tip_len * sa)
        p3 = (216 * ca + w_base * nx, 216 * sa + w_base * ny)
        out.append(stroke_path([p1, p2, p3], width=1.6, opacity=0.90))
        out.append(circle((tip_len + 5.0) * ca, (tip_len + 5.0) * sa, 2.0 if i % 2 == 0 else 1.4, opacity=0.88, fill=True))

    return "".join(out)


# ---------------------------------------------------------------------------
# Plate 1: Poincaré Hyperbolic Disk Tessellation & Architectural Math Grid
# ---------------------------------------------------------------------------
def build_poincare_grid():
    out = []
    R = 192.0

    # Outer architectural blueprint frame & subtle polar degree ticks
    out.append(circle(0, 0, R, width=2.4, opacity=0.95))
    out.append(circle(0, 0, R + 8, width=1.0, opacity=0.55))
    out.append(circle(0, 0, R + 22, width=1.4, opacity=0.75, dash="3 5"))

    # Subtle outer golden-ratio drafting grid lines clipped outside the disk
    for k in range(-4, 5):
        v = k * 54.0
        out.append(stroke_path([(-232, v), (232, v)], width=0.65, opacity=0.22))
        out.append(stroke_path([(v, -232), (v, 232)], width=0.65, opacity=0.22))

    # Degree ticks around the horizon circle
    for i in range(72):
        th = i * TAU / 72.0
        r0 = R + 2.0
        r1 = R + (16.0 if i % 6 == 0 else (10.0 if i % 3 == 0 else 5.5))
        out.append(stroke_path([(r0 * cos(th), r0 * sin(th)), (r1 * cos(th), r1 * sin(th))],
                               width=1.4 if i % 6 == 0 else 0.9, opacity=0.80 if i % 6 == 0 else 0.55))

    # True hyperbolic {4, 5} tessellation via Möbius / circle inversions in the unit disk!
    # A regular hyperbolic p-gon with vertex angle 2*pi/q has circumradius r_v:
    # cos(pi/p) / sin(pi/q) = cosh(d), tanh(d/2) = r_v
    def mobius_geodesic_arc(z1, z2, n=24):
        """Sample exact hyperbolic geodesic between complex points z1, z2 in unit disk."""
        cross = z1.real * z2.imag - z1.imag * z2.real
        if abs(cross) < 1e-4:
            return [(z1.real + (z2.real - z1.real) * i / n, z1.imag + (z2.imag - z1.imag) * i / n) for i in range(n + 1)]
        # Orthogonal circle center c solves 2 Re(conj(c)*z) = 1 + |z|^2
        a1, b1, c1 = 2 * z1.real, 2 * z1.imag, 1.0 + abs(z1) ** 2
        a2, b2, c2 = 2 * z2.real, 2 * z2.imag, 1.0 + abs(z2) ** 2
        det = a1 * b2 - a2 * b1
        cx = (c1 * b2 - c2 * b1) / det
        cy = (a1 * c2 - a2 * c1) / det
        rad = sqrt(max(1e-9, cx * cx + cy * cy - 1.0))
        ang1 = atan2(z1.imag - cy, z1.real - cx)
        ang2 = atan2(z2.imag - cy, z2.real - cx)
        da = (ang2 - ang1 + pi) % TAU - pi
        return [(cx + rad * cos(ang1 + da * i / n), cy + rad * sin(ang1 + da * i / n)) for i in range(n + 1)]

    def reflect_geodesic(z, z1, z2):
        """Reflect point z across hyperbolic geodesic through z1, z2."""
        cross = z1.real * z2.imag - z1.imag * z2.real
        if abs(cross) < 1e-5:
            # Reflection across diameter through z1
            u = z1 / max(abs(z1), 1e-9)
            return u * u * z.conjugate()
        a1, b1, c1 = 2 * z1.real, 2 * z1.imag, 1.0 + abs(z1) ** 2
        a2, b2, c2 = 2 * z2.real, 2 * z2.imag, 1.0 + abs(z2) ** 2
        det = a1 * b2 - a2 * b1
        c = complex((c1 * b2 - c2 * b1) / det, (a1 * c2 - a2 * c1) / det)
        r2 = abs(c) ** 2 - 1.0
        d = z - c
        return c + (r2 / max(abs(d) ** 2, 1e-9)) * d

    # {5, 4}: pentagons meeting 4 per vertex
    p, q = 5, 4
    t_p = cos(pi / p) / sin(pi / q)
    # cosh(d) = t_p => tanh(d/2) = sqrt((t_p - 1)/(t_p + 1))
    r_v = sqrt((t_p - 1.0) / (t_p + 1.0))
    seed = [r_v * complex(cos(k * TAU / p - pi / 2), sin(k * TAU / p - pi / 2)) for k in range(p)]

    def poly_key(poly):
        cx = sum(z.real for z in poly) / len(poly)
        cy = sum(z.imag for z in poly) / len(poly)
        return (round(cx, 3), round(cy, 3))

    visited = {poly_key(seed): seed}
    queue = [(seed, 0)]
    drawn_edges = set()

    while queue:
        poly, depth = queue.pop(0)
        # Draw polygon edges
        for k in range(p):
            z1, z2 = poly[k], poly[(k + 1) % p]
            ek = tuple(sorted([(round(z1.real, 3), round(z1.imag, 3)), (round(z2.real, 3), round(z2.imag, 3))]))
            if ek not in drawn_edges:
                drawn_edges.add(ek)
                arc = mobius_geodesic_arc(z1, z2, n=22 if depth < 2 else 14)
                pts = [(x * R, y * R) for x, y in arc]
                w = max(0.85, 2.2 - depth * 0.34)
                op = max(0.55, 0.96 - depth * 0.08)
                out.append(stroke_path(pts, width=w, opacity=op))

            # Dual radial bisector accent for depth 0 and 1
            if depth <= 1:
                center = sum(poly) / p
                mid = (z1 + z2) * 0.5
                arc_m = mobius_geodesic_arc(center, mid, n=10)
                out.append(stroke_path([(x * R, y * R) for x, y in arc_m], width=0.75, opacity=0.36, dash="2 4"))

            if depth < 4:
                reflected = [reflect_geodesic(z, z1, z2) for z in poly]
                center_r = sum(reflected) / p
                if abs(center_r) < 0.955:
                    key = poly_key(reflected)
                    if key not in visited:
                        visited[key] = reflected
                        queue.append((reflected, depth + 1))

    # Crisp vertex jewels for inner two shells
    for z in seed:
        out.append(circle(z.real * R, z.imag * R, 2.8, opacity=0.95, fill=True))
    out.append(circle(0, 0, 3.2, opacity=0.95, fill=True))

    # Subtle corner registration brackets
    for sx in (-1, 1):
        for sy in (-1, 1):
            out.append(stroke_path([(sx * 212, sy * 228), (sx * 228, sy * 228), (sx * 228, sy * 212)], width=1.6, opacity=0.75))

    return "".join(out)


# ---------------------------------------------------------------------------
# Plate 2: Sumi-e Japanese Ink Scroll (Enso, Bamboo, Crane, Misty Peaks)
# ---------------------------------------------------------------------------
def build_sumie_ink():
    out = []

    # 1. Expressive calligraphic Enso brush circle (sweeping variable-width stroke + dry brush wisps)
    enso_pts, enso_w = [], []
    n_enso = 140
    for i in range(n_enso + 1):
        t = i / n_enso
        ang = -0.35 + t * (TAU * 0.92)
        wobble = 3.2 * sin(ang * 3.0 + 0.5) + 1.8 * cos(ang * 5.0 - 0.8)
        r = 166.0 + wobble
        enso_pts.append((r * cos(ang), r * sin(ang) - 8.0))
        # Thick confident start, slightly narrower dry tail
        w = 13.5 * pow(sin(min(1.0, t * 1.06) * pi * 0.85 + 0.15), 0.7) * (1.0 - 0.55 * pow(t, 2.2))
        enso_w.append(max(1.2, w))
    out.append(tapered_stroke(enso_pts, enso_w, opacity=0.86))

    # Dry-brush (kasure) parallel wisps on the trailing half of the Enso
    for dr, op, sw in [(-5.5, 0.42, 1.6), (5.0, 0.38, 1.3), (8.5, 0.28, 0.9)]:
        wisp = []
        for i in range(45, n_enso + 1):
            t = i / n_enso
            ang = -0.35 + t * (TAU * 0.92)
            r = 166.0 + dr + 2.5 * sin(ang * 4.0)
            wisp.append((r * cos(ang), r * sin(ang) - 8.0))
        out.append(stroke_path(wisp, width=sw, opacity=op))

    # 2. Layered misty mountain ridges (sansui ink silhouettes near lower third)
    def mountain(y_base, amp, freq, phase, x0, x1, w, op):
        pts = []
        for i in range(90):
            t = i / 89.0
            x = x0 + (x1 - x0) * t
            env = pow(sin(t * pi), 0.7)
            y = y_base - env * amp * (0.55 + 0.30 * sin(x * freq + phase) + 0.15 * cos(x * freq * 2.3 - phase))
            pts.append((x, y))
        return stroke_path(pts, width=w, opacity=op)

    out.append(mountain(148, 72, 0.022, 0.4, -225, 225, 2.8, 0.88))
    out.append(mountain(162, 52, 0.031, 2.1, -210, 215, 2.0, 0.68))
    out.append(mountain(178, 34, 0.019, 3.8, -195, 200, 1.5, 0.52))
    # Subtle water reflection mist lines below mountains
    for y_m, x_span, op in [(188, 155, 0.55), (199, 118, 0.42), (210, 82, 0.30)]:
        out.append(stroke_path([(-x_span, y_m), (x_span, y_m)], width=1.4, opacity=op, dash="28 12 10 8"))

    # 3. Slender ink Bamboo stalks on the right side with segmented culm nodes & sweeping leaves
    def bamboo_stalk(x0, y0, lean, segments, seg_h, thickness):
        elems = []
        cx, cy = x0, y0
        for s in range(segments):
            nx = cx + lean * (1.0 + 0.18 * s)
            ny = cy - seg_h
            # Culm segment (slightly tapered)
            w_seg = thickness * (1.0 - s * 0.08)
            elems.append(tapered_stroke([(cx, cy), ((cx + nx) * 0.5 + 1.0, (cy + ny) * 0.5), (nx, ny)],
                                        [w_seg, w_seg * 0.86, w_seg * 0.96], opacity=0.92))
            # Sharp bamboo node ridge
            elems.append(stroke_path([(nx - w_seg * 0.85, ny + 1.5), (nx + w_seg * 0.85, ny - 1.5)],
                                     width=2.0, opacity=0.96))
            # Bamboo leaf clusters at upper nodes
            if s >= 1:
                for side in (-1, 1):
                    if (s + (1 if side > 0 else 0)) % 2 == 0 or s >= 3:
                        bx, by = nx, ny
                        for lf in range(3):
                            ang = (-2.4 + lf * 0.38) if side < 0 else (-0.75 - lf * 0.38)
                            L = 44.0 + (lf % 2) * 16.0 - s * 2.5
                            lpts = []
                            lw = []
                            for k in range(13):
                                u = k / 12.0
                                bend = 11.0 * u * u
                                lx = bx + cos(ang) * L * u
                                ly = by + sin(ang) * L * u + bend
                                lpts.append((lx, ly))
                                lw.append(max(0.4, 5.8 * sin(u * pi) * (1.0 - 0.35 * u)))
                            elems.append(tapered_stroke(lpts, lw, opacity=0.88))
            cx, cy = nx, ny
        return "".join(elems)

    out.append(bamboo_stalk(95, 205, -7.5, 5, 68, 6.2))
    out.append(bamboo_stalk(138, 212, -4.5, 4, 62, 4.4))

    # 4. Graceful soaring Japanese Crane in the upper-left sky
    # Wings (sweeping tapered calligraphic arcs)
    w_left = [(-18, -58), (-58, -96), (-112, -118), (-154, -104)]
    w_right = [(-12, -56), (18, -104), (58, -126), (92, -118)]
    body_pts = [(-86, -42), (-46, -54), (-8, -58), (28, -50), (54, -44)]
    out.append(tapered_stroke(w_left, [4.0, 14.5, 11.0, 1.5], opacity=0.95))
    out.append(tapered_stroke(w_right, [3.8, 12.5, 9.0, 1.2], opacity=0.90))
    out.append(tapered_stroke(body_pts, [1.2, 5.5, 8.2, 3.4, 0.8], opacity=0.96))
    # Trailing legs
    out.append(stroke_path([(-56, -50), (-98, -32)], width=1.6, opacity=0.85))
    out.append(stroke_path([(-52, -48), (-90, -24)], width=1.4, opacity=0.75))

    # 5. Subtle Hanko artist seal stamp in lower-left
    seal = [(-182, 146), (-152, 146), (-152, 176), (-182, 176)]
    out.append(stroke_path(seal, width=1.9, opacity=0.82, closed=True))
    out.append(stroke_path([(-174, 154), (-160, 154), (-167, 154), (-167, 169), (-175, 169), (-159, 169)],
                           width=1.6, opacity=0.78))

    # Floating sakura / ink petals
    for px, py, rot in [(-95, 42, 0.4), (-48, 86, -0.5), (12, 22, 0.9), (-132, -8, -0.3), (38, 72, 0.2)]:
        petal = [
            (px + cos(rot + k * TAU / 8) * (5.5 if k % 2 == 0 else 2.6),
             py + sin(rot + k * TAU / 8) * (3.2 if k % 2 == 0 else 1.8))
            for k in range(8)
        ]
        out.append(fill_path(petal, opacity=0.78))

    return "".join(out)


# ---------------------------------------------------------------------------
# Plate 3: Harmonic Guilloché Rose & Sacred Spirograph
# ---------------------------------------------------------------------------
def build_guilloche_rose():
    out = []

    # Outer precision compass rings
    out.append(circle(0, 0, 214, width=2.0, opacity=0.90))
    out.append(circle(0, 0, 206, width=1.0, opacity=0.58))
    out.append(circle(0, 0, 198, width=1.2, opacity=0.72, dash="2 4"))

    # Family of phase-shifted harmonic hypotrochoids creating luminous guilloché lace
    for layer in range(7):
        phase = layer * (pi / 21.0)
        R_big = 148.0 + layer * 4.2
        r_small = 42.0 - layer * 1.4
        d_arm = 54.0 + layer * 2.2
        pts = []
        steps = 720
        for i in range(steps + 1):
            t = i * (TAU * 3.0) / steps
            x = (R_big - r_small) * cos(t + phase) + d_arm * cos(((R_big - r_small) / r_small) * t - phase * 2.0)
            y = (R_big - r_small) * sin(t + phase) - d_arm * sin(((R_big - r_small) / r_small) * t - phase * 2.0)
            pts.append((x, y))
        op = 0.88 - abs(layer - 3) * 0.12
        w = 1.35 if layer == 3 else 0.95
        out.append(stroke_path(pts, width=w, opacity=op))

    # Inner Lissajous-rose crown (12-fold epitrochoid)
    for k_phase, op in [(0.0, 0.92), (pi / 12.0, 0.65)]:
        pts = []
        for i in range(361):
            t = i * TAU / 360.0
            r = 56.0 + 24.0 * cos(12.0 * t + k_phase) + 8.0 * sin(24.0 * t)
            pts.append((r * cos(t), r * sin(t)))
        out.append(stroke_path(pts, width=1.4, opacity=op))

    # Crisp 24-ray star reticle in the eye
    for i in range(24):
        th = i * TAU / 24.0
        r0 = 14.0 if i % 2 == 0 else 22.0
        r1 = 42.0 if i % 2 == 0 else 34.0
        out.append(stroke_path([(r0 * cos(th), r0 * sin(th)), (r1 * cos(th), r1 * sin(th))], width=1.1, opacity=0.78))
    out.append(circle(0, 0, 14.0, width=1.6, opacity=0.92))
    out.append(circle(0, 0, 4.0, opacity=0.96, fill=True))

    return "".join(out)


# ---------------------------------------------------------------------------
# Seamless 4K Tile 1: Mathematical Star Mosaic (Girih 8-fold Islamic/Math Tessellation)
# Exact periodic repeat across [0, 1000] x [0, 1000] (4x4 fundamental cells of 250)
# ---------------------------------------------------------------------------
def build_mosaic_tile():
    out = []
    cell = 250.0

    def draw_star_cell(cx, cy):
        elems = []
        # 8-pointed Khatam star (two rotated squares) + outer geometric strapwork
        r_outer = 96.0
        r_inner = 68.0
        r_core = 38.0

        # Primary double-line octagonal star
        for scale, w, op in [(1.0, 2.8, 0.95), (0.87, 1.5, 0.72)]:
            pts = []
            for k in range(16):
                th = k * TAU / 16.0
                r = (r_outer if k % 2 == 0 else r_inner) * scale
                pts.append((cx + r * cos(th), cy + r * sin(th)))
            elems.append(stroke_path(pts, width=w, opacity=op, closed=True))

        # Inner 8-pointed rosette & central jewel
        inner_pts = []
        for k in range(16):
            th = k * TAU / 16.0 + TAU / 32.0
            r = r_core if k % 2 == 0 else r_core * 0.56
            inner_pts.append((cx + r * cos(th), cy + r * sin(th)))
        elems.append(stroke_path(inner_pts, width=1.8, opacity=0.88, closed=True))
        elems.append(circle(cx, cy, 10.0, width=1.6, opacity=0.86))
        elems.append(circle(cx, cy, 3.6, opacity=0.94, fill=True))

        # Connecting kite / cross beams to the 4 cardinal & 4 diagonal neighbors (exact periodic tiling!)
        half = cell * 0.5
        for k in range(4):
            th = k * pi * 0.5
            ca, sa = cos(th), sin(th)
            nx, ny = -sa, ca
            # Pointed hexagonal bridge between adjacent star tips
            p0 = (cx + r_outer * ca, cy + r_outer * sa)
            p1 = (cx + (half - 16) * ca + 18 * nx, cy + (half - 16) * sa + 18 * ny)
            p2 = (cx + half * ca, cy + half * sa)
            p3 = (cx + (half - 16) * ca - 18 * nx, cy + (half - 16) * sa - 18 * ny)
            elems.append(stroke_path([p0, p1, p2, p3], width=2.2, opacity=0.90, closed=True))
            elems.append(stroke_path([(cx + (r_outer + 6) * ca, cy + (r_outer + 6) * sa), p2], width=1.1, opacity=0.62))

        # Corner diamond medallions sitting at (cx ± half, cy ± half)
        for sx in (-1, 1):
            for sy in (-1, 1):
                mx, my = cx + sx * half, cy + sy * half
                # Draw subtle quarter-arc/cross connecting diagonal star points
                dpts = [
                    (mx, my - 34), (mx + 14, my - 14), (mx + 34, my), (mx + 14, my + 14),
                    (mx, my + 34), (mx - 14, my + 14), (mx - 34, my), (mx - 14, my - 14),
                ]
                elems.append(stroke_path(dpts, width=2.0, opacity=0.86, closed=True))
                elems.append(circle(mx, my, 6.0, width=1.4, opacity=0.78))
        return "".join(elems)

    # Render across a padded grid so wrapped corners tile seamlessly!
    for gx in range(-1, 5):
        for gy in range(-1, 5):
            out.append(draw_star_cell(gx * cell + cell * 0.5, gy * cell + cell * 0.5))

    return "".join(out)


# ---------------------------------------------------------------------------
# Seamless 4K Tile 2: Traditional Japanese Seigaiha Waves
# Exact periodic repeat across [0, 1000] x [0, 1000]
# ---------------------------------------------------------------------------
def build_seigaiha_tile():
    out = []
    # Seigaiha geometry: horizontal step W = 200 (5 across 1000), vertical row step H = 50 (20 rows across 1000)
    # Odd rows shifted by W/2 = 100. Radius R = 100 => adjacent fans kiss cleanly, next row overlaps smoothly!
    W = 200.0
    H = 62.5  # 16 rows in 1000.0 -> exact integer!
    R = 100.0

    # Because SVG doesn't mask automatically behind arcs, we draw from top to bottom and clip each fan
    # analytically by computing only the visible upper portion above the two overlapping lower-row fans!
    # For a fan centered at (cx, cy), the two overlapping fans in front of it are centered at:
    # (cx - W/2, cy + H) and (cx + W/2, cy + H), each of radius R.
    def is_occluded(x, y, cx, cy):
        for dx in (-W * 0.5, W * 0.5):
            ox, oy = cx + dx, cy + H
            if (x - ox) ** 2 + (y - oy) ** 2 < (R - 1.2) ** 2:
                return True
        # Also occluded by the fan directly below at (cx, cy + 2*H)
        if (x - cx) ** 2 + (y - (cy + 2 * H)) ** 2 < (R - 1.2) ** 2:
            return True
        return False

    radii = [(98.0, 2.8, 0.96), (82.0, 1.9, 0.86), (66.0, 1.6, 0.78), (50.0, 1.4, 0.70), (34.0, 1.3, 0.64), (19.0, 1.2, 0.58)]

    for row in range(-2, 19):
        cy = row * H
        shift = (W * 0.5) if (row % 2 != 0) else 0.0
        for col in range(-1, 7):
            cx = col * W + shift
            for rad, sw, op in radii:
                seg = []
                n = 64
                for i in range(n + 1):
                    # Upper semicircle from pi to 2*pi (in SVG y-down, sin < 0 is upward)
                    th = pi + pi * i / n
                    px, py = cx + rad * cos(th), cy + rad * sin(th)
                    if not is_occluded(px, py, cx, cy):
                        seg.append((px, py))
                    else:
                        if len(seg) >= 2:
                            out.append(stroke_path(seg, width=sw, opacity=op))
                        seg = []
                if len(seg) >= 2:
                    out.append(stroke_path(seg, width=sw, opacity=op))

            # Delicate stipple dots along the r=90 crest of each wave
            for i in range(1, 10):
                th = pi + pi * i / 10.0
                px, py = cx + 90.0 * cos(th), cy + 90.0 * sin(th)
                if not is_occluded(px, py, cx, cy):
                    out.append(circle(px, py, 1.6, opacity=0.72, fill=True))

    return "".join(out)


# ---------------------------------------------------------------------------
# Seamless 4K Tile 3: Ink & Botanical Sketchbook Repeat
# Fine pen-and-ink botanical ginkgo leaves, wave curls, origami cranes, sakura, pine
# ---------------------------------------------------------------------------
def sketch_ginkgo():
    out = []
    # Fan-shaped ginkgo biloba leaf with delicate radiating veins & stem
    pts = [(0, 56), (-3, 24)]
    for i in range(33):
        t = i / 32.0
        ang = -pi * 0.86 + t * (pi * 0.72)
        notch = 1.0 - 0.24 * exp(-((t - 0.5) / 0.06) ** 2)
        wave = 1.0 + 0.03 * sin(t * pi * 9.0)
        r = 66.0 * notch * wave
        pts.append((r * cos(ang), 20.0 + r * sin(ang)))
    pts.append((3, 24))
    out.append(stroke_path(pts, width=2.4, opacity=0.92, closed=True))
    # Radiating fine ink veins
    for i in range(1, 14):
        t = i / 14.0
        if abs(t - 0.5) < 0.05:
            continue
        ang = -pi * 0.84 + t * (pi * 0.68)
        r = 56.0 * (1.0 - 0.18 * exp(-((t - 0.5) / 0.08) ** 2))
        out.append(stroke_path([(0, 20), (r * cos(ang), 20 + r * sin(ang))], width=0.95, opacity=0.58))
    return "".join(out)


def sketch_wave_curl():
    out = []
    # Hokusai-inspired cresting wave ink sketch
    for layer, scale, dy, w, op in [(0, 1.0, 0.0, 2.6, 0.94), (1, 0.82, 10.0, 1.6, 0.72), (2, 0.64, 19.0, 1.2, 0.56)]:
        pts = []
        for i in range(60):
            t = i / 59.0
            ang = 0.2 + t * 4.4
            r = (66.0 - 44.0 * pow(t, 0.85)) * scale
            x = -22 + r * cos(ang) + 28 * (1 - t)
            y = dy + 10 - r * sin(ang) * 0.82
            pts.append((x, y))
        out.append(stroke_path(pts, width=w, opacity=op))
    # Sea-foam spray dots
    for dx, dy, r in [(-58, -18, 2.3), (-68, -6, 1.8), (-52, -32, 1.6), (-36, -42, 2.0), (-74, 8, 1.4)]:
        out.append(circle(dx, dy, r, opacity=0.82, fill=True))
    return "".join(out)


def sketch_origami_crane():
    out = []
    # Crisp geometric folded-paper crane (tsuru)
    body = [(-62, -16), (-18, 8), (22, 8), (64, -26), (12, -2), (-22, -6)]
    wing_l = [(-18, 8), (-42, -52), (12, -2)]
    wing_r = [(2, 4), (36, -54), (22, 8)]
    neck = [(-62, -16), (-74, -2), (-54, -4)]
    out.append(stroke_path(body, width=2.2, opacity=0.92, closed=True))
    out.append(stroke_path(wing_l, width=2.2, opacity=0.94, closed=True))
    out.append(stroke_path(wing_r, width=1.8, opacity=0.84, closed=True))
    out.append(stroke_path(neck, width=2.0, opacity=0.90))
    # Internal paper crease lines
    out.append(stroke_path([(-18, 8), (12, -2)], width=1.1, opacity=0.62, dash="3 4"))
    out.append(stroke_path([(-14, -4), (-42, -52)], width=1.0, opacity=0.52))
    out.append(stroke_path([(12, -2), (36, -54)], width=1.0, opacity=0.52))
    return "".join(out)


def sketch_sakura():
    out = []
    # 5-petal Japanese cherry blossom with notched tips & stamens
    for i in range(5):
        a = i * TAU / 5.0 - pi * 0.5
        half = TAU / 10.0 * 0.80
        pts = [(0, 0)]
        for s in range(19):
            t = s / 18.0
            ang = a - half + 2 * half * t
            notch = 1.0 - 0.16 * exp(-((t - 0.5) / 0.08) ** 2)
            r = 52.0 * pow(sin(t * pi), 0.55) * notch
            pts.append((r * cos(ang), r * sin(ang)))
        out.append(stroke_path(pts, width=2.1, opacity=0.92, closed=True))
        # Fine stamens
        for d_ang in (-0.12, 0.0, 0.12):
            sx, sy = 22 * cos(a + d_ang), 22 * sin(a + d_ang)
            out.append(stroke_path([(0, 0), (sx, sy)], width=1.0, opacity=0.65))
            out.append(circle(sx, sy, 1.8, opacity=0.88, fill=True))
    out.append(circle(0, 0, 5.0, width=1.5, opacity=0.85))
    return "".join(out)


def sketch_fern():
    out = []
    # Delicate botanical fern frond
    stem = [(0, 62), (-4, 24), (2, -16), (10, -58)]
    out.append(stroke_path(stem, width=2.1, opacity=0.90))
    for k in range(9):
        t = (k + 0.8) / 9.8
        sx = -4 * (1 - t) * t * 2 + 10 * t * t
        sy = 62 * (1 - t) - 58 * t
        L = 36.0 * (1.0 - 0.62 * t)
        for side in (-1, 1):
            ang = (-0.55 if side > 0 else -pi + 0.55) + 0.15 * t
            ex, ey = sx + L * cos(ang), sy + L * sin(ang)
            mx, my = (sx + ex) * 0.5, (sy + ey) * 0.5 - 4.0
            out.append(stroke_path([(sx, sy), (mx, my), (ex, ey)], width=1.5, opacity=0.84))
            out.append(stroke_path([(sx, sy), (mx, my + 5.0), (ex, ey)], width=1.1, opacity=0.62))
    return "".join(out)


def sketch_lantern_moon():
    out = []
    # Crescent moon + ink clouds
    outer = [(44 * cos(t), 44 * sin(t)) for t in [-pi * 0.42 + pi * 0.84 * i / 36 for i in range(37)]]
    inner = [(14 + 34 * cos(t), 34 * sin(t)) for t in [pi * 0.42 - pi * 0.84 * i / 36 for i in range(37)]]
    out.append(stroke_path(outer + inner, width=2.2, opacity=0.92, closed=True))
    # Stylized ink cloud ribbons
    for cy, dx, w in [(24, -18, 48), (36, 12, 38)]:
        out.append(stroke_path([(dx - w, cy), (dx + w, cy)], width=1.8, opacity=0.78))
        out.append(curve(lambda t: (dx + w + 8 * cos(t), cy - 6 + 6 * sin(t)), -pi * 0.5, pi * 0.5, n=14, width=1.5, opacity=0.72))
    for sx, sy in [(-38, -28), (-22, -46), (26, -34), (42, -12)]:
        out.append(circle(sx, sy, 2.0, opacity=0.85, fill=True))
    return "".join(out)


def sketch_bamboo_sprig():
    out = []
    out.append(stroke_path([(-18, 58), (-4, 8), (12, -52)], width=2.5, opacity=0.92))
    out.append(stroke_path([(-11, 8), (3, 6)], width=2.0, opacity=0.90))
    for (bx, by, ang, L) in [(-4, 8, -2.5, 42), (-4, 8, -2.0, 36), (4, -22, -0.5, 44), (4, -22, -0.95, 34), (12, -52, -2.2, 30)]:
        pts = []
        ws = []
        for i in range(11):
            u = i / 10.0
            pts.append((bx + cos(ang) * L * u, by + sin(ang) * L * u + 7 * u * u))
            ws.append(max(0.4, 5.2 * sin(u * pi)))
        out.append(tapered_stroke(pts, ws, opacity=0.86))
    return "".join(out)


def build_sketch_tile():
    # Staggered seamless repeat across 1000x1000; wrap motifs near edges for 100% seamless tiling
    motifs = [
        (135, 130, -14, 1.05, sketch_ginkgo()),
        (410, 115, 12, 0.96, sketch_origami_crane()),
        (695, 145, -8, 1.02, sketch_sakura()),
        (915, 110, 16, 0.95, sketch_fern()),
        (245, 370, 9, 1.08, sketch_wave_curl()),
        (545, 355, -12, 1.00, sketch_bamboo_sprig()),
        (825, 380, 14, 1.04, sketch_lantern_moon()),
        (115, 610, 18, 0.98, sketch_sakura()),
        (385, 635, -16, 1.04, sketch_fern()),
        (665, 600, 11, 1.06, sketch_ginkgo()),
        (910, 645, -14, 0.96, sketch_origami_crane()),
        (230, 865, -9, 1.02, sketch_lantern_moon()),
        (525, 880, 13, 1.08, sketch_wave_curl()),
        (810, 860, -17, 1.00, sketch_bamboo_sprig()),
    ]
    out = []
    for x, y, ang, sc, shape in motifs:
        # Wrap copies across boundaries if within 160 units of any edge
        xs = [x] + ([x - 1000] if x > 840 else []) + ([x + 1000] if x < 160 else [])
        ys = [y] + ([y - 1000] if y > 840 else []) + ([y + 1000] if y < 160 else [])
        for tx in xs:
            for ty in ys:
                out.append(f'<g transform="translate({tx} {ty}) rotate({ang}) scale({sc})">{shape}</g>')
    # Fine ink sparkle dots scattered across open spaces
    dots = [(285, 225, 2.5), (565, 225, 3.0), (85, 385, 2.6), (400, 485, 2.8), (735, 490, 2.5),
            (255, 740, 3.0), (540, 745, 2.4), (960, 495, 2.6), (55, 870, 2.5), (675, 290, 2.2)]
    for x, y, r in dots:
        out.append(circle(x, y, r, width=1.6, opacity=0.62))
    return "".join(out)


def render_svg(svg_str: str, out_png: Path):
    subprocess.run(["rsvg-convert", "-o", str(out_png)], input=svg_str.encode("utf-8"), check=True)
    print(f"Wrote {out_png} ({out_png.stat().st_size / 1024:.0f} KB)")


def main():
    ap = argparse.ArgumentParser(description="Generate 4K/8K artistic & math atlases for NotchBanner.")
    ap.add_argument("--out", type=Path, default=ROOT)
    out = ap.parse_args().out
    out.mkdir(parents=True, exist_ok=True)

    # 1. 8192x8192 2x2 Plate Atlas (4x 4K plates: Mandala, Poincaré Grid, Sumi-e Ink, Harmonic Guilloché)
    plates = [
        build_japanese_mandala(),
        build_poincare_grid(),
        build_sumie_ink(),
        build_guilloche_rose(),
    ]
    panels = []
    for i, drawing in enumerate(plates):
        cx = 250 + (i % 2) * 500
        cy = 250 + (i // 2) * 500
        panels.append(f'<g transform="translate({cx} {cy})">{drawing}</g>')
    plates_svg = (
        '<svg xmlns="http://www.w3.org/2000/svg" width="8192" height="8192" viewBox="0 0 1000 1000">'
        + "".join(panels)
        + "</svg>"
    )
    render_svg(plates_svg, out / "banner-art-plates.png")

    # 2. 4096x4096 Seamless Repeating Tiles
    for name, builder in [
        ("banner-mosaic.png", build_mosaic_tile),
        ("banner-seigaiha.png", build_seigaiha_tile),
        ("banner-sketch.png", build_sketch_tile),
    ]:
        svg = (
            '<svg xmlns="http://www.w3.org/2000/svg" width="4096" height="4096" viewBox="0 0 1000 1000">'
            + builder()
            + "</svg>"
        )
        render_svg(svg, out / name)


if __name__ == "__main__":
    main()
