"""Build real vector artwork from the child's drawing and outlined wordmarks.

Requires Pillow and numpy. Run with the bundled workspace Python.
Raster exports are made separately by render.cjs with sharp.
"""
from pathlib import Path
from collections import defaultdict
import json
import hashlib
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SVG = ROOT / 'svg'
SVG.mkdir(exist_ok=True)
im = np.asarray(Image.open(ROOT / 'source/daughter-drawing-preview.png').convert('RGB').resize((1368, 1824)), dtype=float)
r, g, b = im[..., 0], im[..., 1], im[..., 2]
mask = (g > r * 1.28) & (g > b * 1.12) & (g > 35)
mask[:410] = False
mask[940:] = False
mask[:, :280] = False
mask[:, 1040:] = False

def morphology(a, operation):
    p = np.pad(a, 2)
    views = [p[y:y+a.shape[0], x:x+a.shape[1]] for y in range(5) for x in range(5)]
    return np.logical_or.reduce(views) if operation == 'dilate' else np.logical_and.reduce(views)

mask = morphology(morphology(mask, 'dilate'), 'erode')
edges = defaultdict(list)
north = np.zeros_like(mask); north[1:] = mask[:-1]
south = np.zeros_like(mask); south[:-1] = mask[1:]
west = np.zeros_like(mask); west[:, 1:] = mask[:, :-1]
east = np.zeros_like(mask); east[:, :-1] = mask[:, 1:]
for side, neighbor in [('top',north), ('right',east), ('bottom',south), ('left',west)]:
    for y, x in zip(*np.where(mask & ~neighbor)):
        if side == 'top': a, z = (x,y), (x+1,y)
        elif side == 'right': a, z = (x+1,y), (x+1,y+1)
        elif side == 'bottom': a, z = (x+1,y+1), (x,y+1)
        else: a, z = (x,y+1), (x,y)
        edges[a].append(z)
loops = []
while edges:
    start = next(iter(edges)); current = start; loop = [start]
    while current in edges:
        following = edges[current].pop()
        if not edges[current]: del edges[current]
        current = following
        loop.append(current)
        if current == start: break
    loops.append(loop)
contour = max(loops, key=len)

def rdp(points, epsilon):
    if len(points) < 3: return points
    a, z = np.array(points[0]), np.array(points[-1])
    values = np.array(points[1:-1])
    line = z-a
    distances = np.linalg.norm(values-a, axis=1) if not np.any(line) else abs(line[0]*(a[1]-values[:,1])-line[1]*(a[0]-values[:,0])) / np.linalg.norm(line)
    index = int(np.argmax(distances)) + 1
    if distances[index-1] > epsilon:
        return rdp(points[:index+1],epsilon)[:-1]+rdp(points[index:],epsilon)
    return [points[0],points[-1]]

half = len(contour)//2
points = rdp(contour[:half+1], 4.0)[:-1] + rdp(contour[half:], 4.0)[:-1]
minimum = np.array(contour).min(axis=0)
maximum = np.array(contour).max(axis=0)
scale = 660 / (maximum[0]-minimum[0])
normalized = [((float(x)-minimum[0])*scale+70, (float(y)-minimum[1])*scale+65) for x,y in points]

def curved(points):
    n = len(points)
    fmt = lambda p: f'{p[0]:.2f} {p[1]:.2f}'
    d = 'M'+fmt(points[0])
    for i in range(n):
        previous = np.array(points[(i-1)%n]); a = np.array(points[i]); z = np.array(points[(i+1)%n]); following = np.array(points[(i+2)%n])
        c1 = a+(z-previous)/10
        c2 = z-(following-a)/10
        d += ' C'+fmt(c1)+' '+fmt(c2)+' '+fmt(z)
    return d+' Z'

crown = curved(normalized)
green, brown, paper, ink = '#167454', '#B9784D', '#F7F5ED', '#243B32'
trunk_x = (610-minimum[0])*scale+70
join_y = (864-minimum[1])*scale+65
trunk = f'M {trunk_x-10:.2f} {join_y-12:.2f} C {trunk_x-6:.2f} 615 {trunk_x-20:.2f} 708 {trunk_x-18:.2f} 754 Q {trunk_x-17:.2f} 767 {trunk_x-6:.2f} 766 Q {trunk_x+5:.2f} 765 {trunk_x+7:.2f} 755 C {trunk_x+8:.2f} 680 {trunk_x+12:.2f} 600 {trunk_x+12:.2f} {join_y-12:.2f} Z'

# A few intentional vector pencil strokes echo the original pigment direction.
strokes = [
    'M 372 132 C 336 210 307 280 244 346',
    'M 430 216 C 477 279 528 312 572 337',
    'M 231 445 Q 191 490 157 510',
    'M 357 449 Q 339 474 319 494',
    'M 509 445 Q 547 467 589 480',
]
def mark(monochrome=False, texture=True, reversed=False):
    c = paper if reversed else (ink if monochrome else green)
    t = c if monochrome or reversed else brown
    shapes = f'<path id="trunk" fill="{t}" d="{trunk}"/><path id="crown" fill="{c}" d="{crown}"/>'
    if texture and not monochrome and not reversed:
        shapes += '<g id="pencil-strokes" fill="none" stroke="#B6DCCE" stroke-width="5" stroke-linecap="round" opacity=".22">' + ''.join(f'<path d="{p}"/>' for p in strokes) + '</g>'
    return shapes

def svg(name, width, height, content, description):
    s = f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">
<title id="title">森学 SenLearn · {description}</title>
<desc id="desc">Derived from the user's daughter's two-tier green tree drawing. True vector paths; no embedded raster images, fonts, or external resources.</desc>
{content}
</svg>
'''
    (SVG / name).write_text(s, encoding='utf-8')

words = json.loads((ROOT/'source/wordmark-outlines.json').read_text())
def wordmark(color=ink):
    return f'<g id="wordmark" fill="{color}"><path aria-label="森学" transform="translate(475 248)" d="{words["zh"]["path"]}"/><path aria-label="SenLearn" transform="translate(480 365)" d="{words["en"]["path"]}"/></g>'

svg('senlearn-app-icon.svg',1024,1024, f'<rect width="1024" height="1024" fill="{paper}"/><g transform="translate(102 80) scale(1.025)">{mark()}</g>', 'app icon')
svg('senlearn-mark.svg',800,830, mark(), 'tree mark')
svg('senlearn-mark-small.svg',800,830, mark(texture=False), 'small-size tree mark')
svg('senlearn-logo-horizontal.svg',1120,460, f'<g transform="translate(38 30) scale(.49)">{mark()}</g>{wordmark()}', 'horizontal bilingual logo')
svg('senlearn-logo-monochrome.svg',1120,460, f'<g transform="translate(38 30) scale(.49)">{mark(monochrome=True)}</g>{wordmark()}', 'one-color logo')
svg('senlearn-logo-reverse.svg',1120,460, f'<g transform="translate(38 30) scale(.49)">{mark(reversed=True)}</g>{wordmark(paper)}', 'reversed logo')
svg('senlearn-logo-stacked.svg',800,1120, f'<g transform="translate(120 15) scale(.7)">{mark()}</g><path fill="{ink}" transform="translate(230 818)" d="{words["zh"]["path"]}"/><path fill="{ink}" transform="translate(205 958) scale(.86)" d="{words["en"]["path"]}"/>', 'stacked bilingual logo')
svg('senlearn-mark-monochrome.svg',800,830, mark(monochrome=True), 'one-color tree mark')
svg('senlearn-app-icon-dark.svg',1024,1024,f'<rect width="1024" height="1024" fill="#172E26"/><g transform="translate(102 80) scale(1.025)">{mark(reversed=True)}</g>', 'dark app icon')

# Preserve the original silhouette and its long trunk as a separate source trace.
original_trunk = 'M607 860 L628 860 C622 1010 620 1170 616 1335 Q613 1351 602 1347 Q590 1347 591 1335 C598 1160 590 1000 607 860 Z'
raw_crown = curved([(float(x),float(y)) for x,y in points])
svg('daughter-tree-trace.svg',800,1080, f'<g transform="translate(-255 -370)"><path fill="{brown}" d="{original_trunk}"/><path fill="{green}" d="{raw_crown}"/></g>', 'original drawing silhouette trace')

manifest = {
    'brand': '森学 · SenLearn', 'date': '2026-10-11',
    'boardId': 'a66d5431-c5ef-4f11-966e-01629342d41f',
    'source': '../手绘图标素材.heic',
    'source_sha256': hashlib.sha256((ROOT.parent/'手绘图标素材.heic').read_bytes()).hexdigest(),
    'route': 'Source-derived deterministic vector artwork; no AI raster generation',
    'preserved': ['two asymmetric crown tiers', 'left-offset apex', 'green crown', 'thin brown trunk'],
    'adapted': ['trunk shortened for small-size recognition', 'contour simplified and softly smoothed', 'five subtle vector pencil strokes', 'warm paper app-icon background'],
    'palette': {'tree': green, 'trunk': brown, 'paper':paper, 'ink':ink},
    'wordmarks': {k:{a:v for a,v in words[k].items() if a!='path'} for k in words},
    'exports': [{'svg':f'svg/{p.name}', 'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(SVG.glob('*.svg'))],
}
(ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
print(json.dumps({'contourPoints':len(points),'sourceBounds':[minimum.tolist(), maximum.tolist()],'exports':len(manifest['exports'])}))
