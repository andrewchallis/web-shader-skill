# Gas giant cloud snippets (TSL)

Short, working pieces from Jupiter's Nightscape-style cloud (Elsewhere,
`src/universe-route/nightscape-clouds.js` and `gas-giant.js`, Nov 2026),
trimmed to stand alone. They are the parts that took many rounds to get
right. Read [gas-giant-clouds.md](gas-giant-clouds.md) first for why each
exists.

Three.js r186-r187, `three/webgpu` and `three/tsl`. Inputs are named in
comments; wire them to your own uniforms. The code ran in the app on WebGPU.
On this page it is renamed and trimmed: snippets 1 and 4-8 were built
together into one material and compiled to WGSL without errors (headless
Chromium, software WebGPU, 11 Nov 2026). The JS-only parts of 2, 3 and 7
weren't run as trimmed here. Check them in your own build.

**Licence.** Shared by the project's owner under this skill's MIT licence.
The strip bake (snippet 2) is part of a bake adapted from
[Nightscape](https://github.com/WeebLabs/Nightscape) by Weeb Labs (MIT,
Copyright (c) 2026 Weeb Labs); keep that notice with it. Nothing here comes
from Liard's Overcast Cloud (CC BY-NC-SA).

## 1. A gnomonic chart fixed to the planet

A flat-world cloud (Nightscape's 320-unit tile) needs a local frame on a
sphere. A gnomonic chart round an anchor direction `c0` keeps lines of
constant chart z as planes through the planet's centre, so a ray meets one
exactly. Don't scale across by height: a height factor put the planes 0.4
to 4% off and drew slab steps.

```js
import * as THREE from 'three/webgpu';
import { uniform, vec3, dot, length, abs, select, float } from 'three/tsl';

// radiusKm: the planet's radius; kmPerUnit: chart unit (Jupiter: 14 km);
// baseKm: height of unit 0 over the unit sphere (Jupiter: 110 km).
export function planetChart({ radiusKm, kmPerUnit, baseKm }) {
  const S = radiusKm / kmPerUnit; // units per planet radius
  const c0 = uniform(new THREE.Vector3(0, 0, 1));  // anchor (set once, below)
  const ex0 = uniform(new THREE.Vector3(1, 0, 0)); // across
  const ez0 = uniform(new THREE.Vector3(0, 1, 0)); // along
  // p: a point in planet space (unit sphere, the planet's own frame).
  const toUnits = p => {
    const dn = dot(p, c0);
    return vec3(
      dot(p, ex0).div(dn).mul(S),
      length(p).sub(1).mul(radiusKm).sub(baseKm).div(kmPerUnit),
      dot(p, ez0).div(dn).mul(S));
  };
  // Ray e + rd t (t in radii) meets chart z = zn at:
  const planeT = (e, rd, zn) => {
    const v = ez0.mul(S).sub(c0.mul(zn));
    const den = dot(rd, v);
    return select(abs(den).greaterThan(1e-7), dot(e, v).negate().div(den), float(1e6));
  };
  return { S, c0, ex0, ez0, toUnits, planeT };
}

// Anchor once, when the camera first comes near (JS). look: the camera's
// view direction in planet space; cam: the camera in planet space.
export function anchorChart(chart, cam, look) {
  const c = chart.c0.value.copy(cam).normalize();
  const fwd = look.clone().addScaledVector(c, -look.dot(c));
  if (fwd.lengthSq() < 1e-8) fwd.set(0, 1, 0).addScaledVector(c, -c.y);
  fwd.normalize();
  chart.ez0.value.copy(fwd).negate();
  chart.ex0.value.crossVectors(chart.ez0.value, c).normalize();
}
```

Measure heights over the planet's own flattened deck in the space the
shader uses (here the mesh's local, unflattened space), never from an
app's km readout.

## 2. Bake a window in scissored strips (three r186-r187, WebGPU)

A few strips a frame, taking turns between levels. Two traps, both silent:
three applies a target's scissor only while the renderer's scissor test
is on, and WebGPU clears the whole target per pass whatever the scissor.
A WebGL harness hides the second one.

```js
// targets: two render targets (front/back) holding a 2D atlas of Z height
// tiles, R x R texels each, COLS tiles across. quad: a QuadMesh whose
// material bakes one texel (it reads `origin`, the window corner).
// SPT: strips per tile. perFrame / perFirst: strips a frame, normal and
// urgent (first bake, or the camera has left the window far behind).
function bakeStrips(renderer, quad, back, state, { R, Z, COLS, SPT, perFrame, perFirst }) {
  const N = Z * SPT, h = R / SPT;
  const from = state.next, to = Math.min(N, from + (state.urgent ? perFirst : perFrame));
  const previous = renderer.getRenderTarget();
  const scissorWas = renderer.getScissorTest(), clearWas = renderer.autoClear;
  renderer.setScissorTest(true);   // without this every strip drew the whole atlas
  renderer.autoClear = false;      // WebGPU's clear ignores the scissor
  renderer.setRenderTarget(back);
  for (let k = from; k < to; k++) {
    const tile = Math.floor(k / SPT), part = k % SPT;
    back.scissor.set((tile % COLS) * R, Math.floor(tile / COLS) * R + part * h, R, h);
    quad.render(renderer);
  }
  renderer.setScissorTest(scissorWas);
  renderer.autoClear = clearWas;
  renderer.setRenderTarget(previous);
  state.next = to;
  return to >= N; // done: swap front and back
}
```

Set `back.scissorTest = true` on the targets when you create them. Keep
each tile at most 8,192 texels on a side (WebGPU's default limit); lay
the heights out as a grid of tiles, not one column.

Pace: all levels at once drew 87 ms GPU frames on the dive; one strip a
frame took 8-10 s and the dive showed no cloud. 8 strips a turn for first
and urgent bakes, a quarter of a height a frame otherwise, worked.

## 3. Snap the window and fade a swap in

```js
// JS, when a new bake starts: snap the corner to the texel grid, so the
// overlap re-bakes the same values and near rims don't shift at each swap.
const tx = W / R; // window size in units / texels
origin.value.set(Math.round(corner.x / tx) * tx, Math.round(corner.y / tx) * tx);

// JS, when the bake finishes (not the first one):
prevRead.value.copy(read.value); swapAt = performance.now(); swapFade.value = 0;
read.value.copy(origin.value);

// JS, every frame (real time, so it finishes while paused):
swapFade.value = Math.min(1, (performance.now() - swapAt) / 500);
```

```js
import { uniform, smoothstep, min, max, float, select } from 'three/tsl';

const prevRead = uniform(new THREE.Vector2(1e9, 1e9)), swapFade = uniform(1);
// x, z: the point's place in the window, 0-1. 1 well inside, 0 at the
// edge: the level fades into the next coarser one over the outer fifth
// (a tenth showed a seam).
const edgeOf = (x, z) => smoothstep(0.02, 0.2, min(min(x, float(1).sub(x)), min(z, float(1).sub(z))));
// P: chart point; W: window size in units.
const edgeAt = (P, x, z) => {
  const xo = P.x.sub(prevRead.x).div(W), zo = P.z.sub(prevRead.y).div(W);
  const inOld = xo.greaterThan(0).and(xo.lessThan(1)).and(zo.greaterThan(0)).and(zo.lessThan(1));
  const held = select(inOld, edgeOf(xo, zo), float(0));
  // Ground the old window already held shows at once; new ground fades in.
  return edgeOf(x, z).mul(max(held, swapFade));
};
```

## 4. Cubic B-spline read from four filtered taps

Plain bilinear creases at every texel. On coarse baked levels seen from
high up those creases drew horizontal hatching. Four filtered taps give a
smooth cubic B-spline.

```js
import { float, floor, mix, vec2 } from 'three/tsl';

// c: coordinate 0-1 along one axis; R: texels on that axis.
const bspline = (c, R) => {
  const tc = c.mul(R).sub(0.5), i = floor(tc), f = tc.sub(i);
  const f2 = f.mul(f), f3 = f2.mul(f);
  const w0 = float(1).sub(f).pow(3).div(6);
  const w1 = f3.mul(3).sub(f2.mul(6)).add(4).div(6);
  const w3 = f3.div(6);
  const g0 = w0.add(w1);
  return {
    g0,
    p0: i.sub(0.5).add(w1.div(g0)).div(R),
    p1: i.add(1.5).add(w3.div(float(1).sub(g0))).div(R)
  };
};
// at(u, v): one filtered read, e.g. tex.sample(vec2(u, v)).level(0),
// clamped half a texel inside its own tile in an atlas.
const readSmooth = (at, x, z, R) => {
  const X = bspline(x, R), Z = bspline(z, R);
  return mix(
    mix(at(X.p1, Z.p1), at(X.p0, Z.p1), X.g0),
    mix(at(X.p1, Z.p0), at(X.p0, Z.p0), X.g0),
    Z.g0);
};
```

## 5. Coarse height-field march with a bisected crossing

The far 2.5D march finds where a ray first goes below the cloud tops. On
walls steeper than one step, taking the crossing from the coarse step drew
horizontal ribs. Five bisections of the last step, then a straight-line
crossing, follow the wall itself.

```js
import { float, mix, clamp, max, Loop, If, Break } from 'three/tsl';

// gapAt(t): signed gap at ray distance t, negative inside the cloud. For
// slabs: max(above the top, below the underside, outside the clump edge).
// tA, tEnd: the ray's span through the cloud slab. N: coarse steps.
function marchToCloud(gapAt, tA, tEnd, N, refine = 5) {
  const tHit = float(tEnd).toVar(), found = float(0).toVar();
  const tPrev = tA.toVar(), dPrev = gapAt(tA).toVar();
  const tCo = tA.toVar(), dCo = float(0).toVar();
  Loop(N, ({ i }) => {
    const t = mix(tA, tEnd, float(i).add(1).div(N));
    const d = gapAt(t);
    If(d.lessThanEqual(0), () => {
      tCo.assign(t); dCo.assign(d); found.assign(1);
      Break();
    });
    dPrev.assign(d); tPrev.assign(t);
  });
  If(found.greaterThan(0.5), () => {
    const lo = tPrev.toVar(), hi = tCo.toVar(), dLo = dPrev.toVar(), dHi = dCo.toVar();
    Loop(refine, () => {
      const m = lo.add(hi).mul(0.5);
      const d = gapAt(m);
      If(d.lessThanEqual(0), () => { hi.assign(m); dHi.assign(d); })
        .Else(() => { lo.assign(m); dLo.assign(d); });
    });
    tHit.assign(mix(lo, hi, clamp(dLo.div(max(dLo.sub(dHi), 1e-4)), 0, 1)));
  });
  return { tHit, found };
}
```

Give every TSL variable in a long shader its own name: a second `const`
with the same name as one in an outer scope (here `tIn`) failed only at
WGSL build time.

## 6. Thin volume after the first hit (far clumps that aren't rocks)

An opaque top lit like ground reads as rock. A dozen density samples over
a short span from half a step before the hit thin the outlines, let light
in and glow at the edges. Start from the hit, not a grid (ribs) or a hash
jitter (speckle).

```js
import { float, smoothstep, exp, max, min, mix, clamp, Loop, If, Break, select } from 'three/tsl';

// Per sample at ray distance t, you supply cloudAt(t) -> { H (top),
// bot (underside), clump (0-1 coverage), y (sample height) }, in units.
// steps 12, span 30 units, k 0.5, soft [1.5, 1], sun 0.35, powder 0.8.
function thinVolume(cloudAt, tHit, found, tA, tEnd, o = {}) {
  const M = o.steps ?? 12, SO = o.soft ?? [1.5, 1];
  const dt0 = float(o.span ?? 30).div(M);
  const tS = select(found.greaterThan(0.5), max(tHit.sub(dt0.mul(0.5)), tA), tEnd);
  const dt = max(min(tEnd.sub(tS), float(o.span ?? 30)), 0).div(M);
  const T = float(1).toVar(), sun = float(0).toVar(), sky = float(0).toVar();
  Loop(M, ({ i }) => {
    const t = tS.add(dt.mul(float(i).add(0.5)));
    const c = cloudAt(t);
    const dens = smoothstep(0, SO[0], c.H.sub(c.y))      // thin toward the top
      .mul(smoothstep(0, SO[1], c.y.sub(c.bot)))         // and the underside
      .mul(smoothstep(0.04, 0.3, c.clump))
      .mul(o.k ?? 0.5);
    const a = float(1).sub(exp(dens.mul(dt).negate()));
    const od = max(c.H.sub(c.y), 0).mul(o.sun ?? 0.35); // depth to the top, toward a high Sun
    const sunL = exp(od.negate()).mul(mix(float(1), float(1).sub(exp(od.mul(-2).sub(0.15))), o.powder ?? 0.8));
    const up = clamp(c.y.sub(c.bot).div(max(c.H.sub(c.bot), 0.5)), 0, 1);
    const w = T.mul(a);
    sun.addAssign(w.mul(sunL));
    sky.addAssign(w.mul(mix(float(0.45), float(1), up)));
    T.mulAssign(float(1).sub(a));
    If(T.lessThan(0.02), () => { Break(); });
  });
  // Shade with sun and sky, then let the deck under the slabs show by T.
  return { T, sun, sky };
}
```

## 7. A 2.5D storm as a domain warp, fixed to the planet

The storm swirls the clump pattern's coordinates, adds log-spiral arms,
an asymmetric eye wall and a partly clear eye. It returns warped x, z for
the clump noise, a signal to add to coverage (`sg`) and a height lift.

```js
import { float, sqrt, exp, cos, sin, atan, log, max, smoothstep, select } from 'three/tsl';

// x, z: chart coordinates (units); C: the storm centre (a vec2 uniform).
// Jupiter defaults: radius 150 units (about 2,100 km), eye 10, swirl 2.5.
function stormAt(x, z, C, o = {}) {
  const R = o.radius ?? 150, Re = o.eye ?? 10, turn = o.turn ?? 1;
  const dx = x.sub(C.x), dz = z.sub(C.y);
  const rr = max(sqrt(dx.mul(dx).add(dz.mul(dz))), 0.5);
  const fall = exp(rr.div(R).pow(2).negate());
  const ang = fall.mul((o.swirl ?? 2.5) * turn); // strong swirl combs clumps into smears
  const ca = cos(ang), sa = sin(ang);
  const th = atan(dz, dx).mul(turn);
  const arm = cos(th.sub(log(rr).mul(o.wind ?? 2.2)).mul(o.arms ?? 3)).mul(0.5).add(0.5);
  const armM = smoothstep(0.3, 0.75, arm).mul(smoothstep(Re * 2, Re * 4, rr));
  // Eye wall: steep inside, long slope outside (a symmetric ring read as a crater).
  const dw = rr.sub(Re * 1.5);
  const wall = exp(dw.div(select(dw.lessThan(0), float(Re * 0.6), float(Re * (o.wallOut ?? 2.5)))).pow(2).negate());
  const eye = smoothstep(Re * 1.1, Re * 0.5, rr).mul(o.eyeClear ?? 0.6);
  return {
    x: dx.mul(ca).sub(dz.mul(sa)).add(C.x),
    z: dx.mul(sa).add(dz.mul(ca)).add(C.y),
    sg: fall.mul(armM.sub(0.4)).mul(o.armK ?? 2.5).add(wall.mul(o.wallK ?? 2)).sub(eye.mul(4)),
    lift: fall.mul(armM).add(wall.mul(o.wallH ?? 0.8)).mul(o.height ?? 6)
  };
}
```

Place it from a planet-fixed direction as soon as the chart anchors (JS),
before the cloud shows. Setting it later re-swirls every clump within its
radius in one frame.

```js
// dir: the storm's spot on the planet, planet space.
const d = new THREE.Vector3(...dir).normalize(), dn = d.dot(chart.c0.value);
if (dn > 0.05) stormC.value.set(
  d.dot(chart.ex0.value) / dn * chart.S,
  d.dot(chart.ez0.value) / dn * chart.S);
```

## 8. Octaves faded by pixel footprint

Each clump octave fades in once its cells cover a few pixels, so none turns
to grain. `fpx` is the size of a pixel at the sample (ray distance times the
pixel's angle).

```js
import { float, smoothstep, max, vec3 } from 'three/tsl';

// worley(p): a tiling Worley read, mean WORLEY_MEAN. octs: [size, weight].
// tt: ray distance (units); pixelAngle: radians per pixel.
function clumpSignal(worley, WORLEY_MEAN, x, z, h, tt, pixelAngle, octs, px = [2, 5]) {
  const fpx = max(tt.mul(pixelAngle), 1e-4);
  let sum = float(0), shown = float(0);
  const tot = octs.reduce((a, [, w]) => a + w, 0);
  octs.forEach(([u, w], i) => {
    const f = smoothstep(px[0], px[1], float(u).div(fpx)).mul(w);
    sum = sum.add(worley(vec3(x, h.mul(0.3), z).div(u).add(vec3(17.3, 5.1, 9.7).mul(i))).sub(WORLEY_MEAN).mul(f));
    shown = shown.add(f);
  });
  return { r: sum.div(tot).mul(6), vis: shown.div(tot) };
}
```

## 9. Light settings that lifted the black gaps

Not code, but the numbers matter. With heaps lit by a Sun march, these lifted
near-black gaps between near heaps to dark brown with shapes, at no measured
cost. Brightening the floor did nothing.

| Setting | Before | After |
| --- | --- | --- |
| Multiple-scattering shares (two wider light paths) | 0.7, 0.35 | 1.3, 0.9 |
| Sky light | 1.4 | 3 |
| Sky-light floor in shade | 0.28 | 0.6 |
| Floor shadow minimum | 0.5 | 0.8 |
