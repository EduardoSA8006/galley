"""Gera a logo do Galley em SVG com geometria regular.

Três placas idênticas (páginas/livros) em projeção 2:1, deslocadas ao longo
da linha de base L (inclinação -1/2), todas cortadas pela mesma L. Fita
vertical centralizada no vão entre a placa da frente e a do meio.
Vãos são recortados com máscara (fundo transparente).
"""
import math, sys, os
E = lambda k, d: float(os.environ.get(k, d))

W = 300.0          # largura horizontal de cada placa
H = E("H", 190.0)          # altura da aresta esquerda
STEP = 80.0        # deslocamento horizontal entre placas (vertical = -STEP/2)
GAP = 14.0         # vão entre placas
R_BIG = E("RBIG", 66.0)       # raio dos cantos externos
R_SMALL = 10.0     # raio dos cantos da base

def slab(ox, oy):
    """Pentágono da placa: TL, TR, R (base direita), B (bico), BL."""
    tl = (ox, oy)
    tr = (ox + W, oy + W / 2)
    bl = (ox, oy + H)
    # linha L passa por bl + (W*0.74, ...): definimos L pela placa da frente
    return tl, tr, bl

# placa da frente com origem em (0,0); L: y = c - x/2
FRONT = (0.0, 0.0)
# bico B onde a aresta inferior (y = H + x/2) encontra L; escolhemos B.x
BX = W * 0.74
C = H + BX / 2 + BX / 2   # y_L(x) = C - x/2  -> em x=BX: H + BX/2
def yL(x): return C - x / 2

def slab_pts(k):
    dx, dy = k * STEP, -k * STEP / 2
    tl = (0 + dx, 0 + dy)
    tr = (W + dx, W / 2 + dy)
    r = (W + dx, yL(W + dx))          # L é invariante ao deslocamento
    b = (BX + dx, yL(BX + dx))
    bl = (0 + dx, H + dy)
    return [tl, tr, r, b, bl]

def rounded(pts, radii):
    """Caminho fechado com cantos arredondados por arcos tangentes."""
    n = len(pts)
    segs = []
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        r = radii[i]
        v1 = (p0[0] - p1[0], p0[1] - p1[1]); l1 = math.hypot(*v1)
        v2 = (p2[0] - p1[0], p2[1] - p1[1]); l2 = math.hypot(*v2)
        u1 = (v1[0] / l1, v1[1] / l1); u2 = (v2[0] / l2, v2[1] / l2)
        ang = math.acos(max(-1, min(1, u1[0] * u2[0] + u1[1] * u2[1])))
        t = r / math.tan(ang / 2)
        a = (p1[0] + u1[0] * t, p1[1] + u1[1] * t)
        bpt = (p1[0] + u2[0] * t, p1[1] + u2[1] * t)
        cross = u1[0] * u2[1] - u1[1] * u2[0]
        sweep = 0 if cross > 0 else 1
        segs.append((a, bpt, r, sweep))
    d = f"M{segs[0][1][0]:.2f},{segs[0][1][1]:.2f}"
    for i in range(1, n + 1):
        a, bpt, r, sweep = segs[i % n]
        d += f" L{a[0]:.2f},{a[1]:.2f} A{r:.2f},{r:.2f} 0 0 {sweep} {bpt[0]:.2f},{bpt[1]:.2f}"
    return d + " Z"

RADII = [R_BIG, R_BIG, R_SMALL, R_SMALL, R_BIG]
paths = [rounded(slab_pts(k), RADII) for k in range(3)]

# fita: centrada no vão entre a frente (x=W) e o meio; topo paralelo a L, abaixo do vão
RW = E("RW", 72.0)
RC = W + GAP / 2
RL, RR = RC - RW / 2, RC + RW / 2
RLEN = E("RLEN", 120.0)        # comprimento medido no centro
NOTCH = 26.0
def ytop(x): return yL(x) + GAP
TOP = W / 2 if E("TUCK", 1) else None
ribbon = [
    (RL, TOP if TOP is not None else ytop(RL)), (RR, TOP if TOP is not None else ytop(RR)),
    (RR, ytop(RC) + RLEN), (RC, ytop(RC) + RLEN - NOTCH), (RL, ytop(RC) + RLEN),
]
ribbon_d = rounded(ribbon, [3, 3, 3, 4, 3])

# enquadramento
xs = [p[0] for k in range(3) for p in slab_pts(k)] + [p[0] for p in ribbon]
ys = [p[1] for k in range(3) for p in slab_pts(k)] + [p[1] for p in ribbon]
minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
size = max(maxx - minx, maxy - miny) * 1.30
cx, cy = (minx + maxx) / 2, (miny + maxy) / 2
vb = f"{cx - size/2:.2f} {cy - size/2:.2f} {size:.2f} {size:.2f}"

PRIMARY = "#0175C2"      # Flutter Blue
PRIMARY_LIGHT = "#13B9FD"  # Flutter Sky
SECONDARY = "#02569B"    # Flutter Navy
SECONDARY_DARK = "#01447A"
RED = "#E53935"
RED_DARK = "#C62828"

gapw = GAP * 2
SEAM = E("SEAM", 0)
seam = ""
if SEAM:
    sx = W + GAP / 2
    seam = f'  <line x1="{sx}" y1="{W/2 + R_BIG*0.6:.2f}" x2="{sx}" y2="{yL(sx)+GAP:.2f}" stroke="{RED}" stroke-width="{SEAM}" stroke-linecap="round"/>\n'
rgapw = GAP * E("RGAP", 2.0)
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}" width="512" height="512" role="img" aria-label="Galley">
  <title>Galley</title>
  <defs>
    <linearGradient id="gFront" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{PRIMARY_LIGHT}"/>
      <stop offset="1" stop-color="{PRIMARY}"/>
    </linearGradient>
    <linearGradient id="gMid" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{SECONDARY}"/>
      <stop offset="1" stop-color="{SECONDARY_DARK}"/>
    </linearGradient>
    <linearGradient id="gBack" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{PRIMARY}"/>
      <stop offset="1" stop-color="{SECONDARY}"/>
    </linearGradient>
    <linearGradient id="gRibbon" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{RED_DARK}"/>
      <stop offset="0.35" stop-color="{RED}"/>
    </linearGradient>
    <mask id="mBack" maskUnits="userSpaceOnUse" x="-1000" y="-1000" width="3000" height="3000">
      <rect x="-1000" y="-1000" width="3000" height="3000" fill="#fff"/>
      <path d="{paths[1]}" fill="#000" stroke="#000" stroke-width="{gapw}" stroke-linejoin="round"/>
      <path d="{paths[0]}" fill="#000" stroke="#000" stroke-width="{gapw}" stroke-linejoin="round"/>
    </mask>
    <mask id="mMid" maskUnits="userSpaceOnUse" x="-1000" y="-1000" width="3000" height="3000">
      <rect x="-1000" y="-1000" width="3000" height="3000" fill="#fff"/>
      <path d="{paths[0]}" fill="#000" stroke="#000" stroke-width="{gapw}" stroke-linejoin="round"/>
    </mask>
    <mask id="mRibbon" maskUnits="userSpaceOnUse" x="-1000" y="-1000" width="3000" height="3000">
      <rect x="-1000" y="-1000" width="3000" height="3000" fill="#fff"/>
      <path d="{paths[0]}" fill="#000" stroke="#000" stroke-width="{rgapw}" stroke-linejoin="round"/>
      <path d="{paths[1]}" fill="#000" stroke="#000" stroke-width="{rgapw}" stroke-linejoin="round"/>
      <path d="{paths[2]}" fill="#000" stroke="#000" stroke-width="{rgapw}" stroke-linejoin="round"/>
    </mask>
  </defs>
  <path d="{ribbon_d}" fill="url(#gRibbon)" mask="url(#mRibbon)"/>
  <path d="{paths[2]}" fill="url(#gBack)" mask="url(#mBack)"/>
  <path d="{paths[1]}" fill="url(#gMid)" mask="url(#mMid)"/>
{seam}  <path d="{paths[0]}" fill="url(#gFront)"/>
</svg>
'''
open(sys.argv[1], "w").write(svg)
