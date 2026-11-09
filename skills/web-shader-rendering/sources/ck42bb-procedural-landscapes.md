# CK42BB procedural-landscapes-threejs

From [procedural-landscapes-threejs](https://github.com/CK42BB/procedural-landscapes-threejs), Kingsley (CK42BB), commit `f7c147a`, MIT (notice at the end). Terrain from FBM, ridged multifractal, domain warp and terraces; WGSL compute heightmap, normals and hydraulic erosion; water, sky and vegetation scattering. Teaching samples, not tested at Elsewhere's scales; read for ideas and port to TSL. Each original file follows unchanged.

---

<!-- file: SKILL.md -->

---
name: procedural-landscapes
description: >
  Generate procedural 3D landscapes and terrain in Three.js using WebGPU compute
  shaders with automatic WebGL2 fallback. Covers heightmap generation via FBM noise,
  ridged multifractal, and domain warping; chunked LOD terrain meshes; slope-based
  multi-material texturing; procedural water planes; atmospheric sky rendering;
  and instanced vegetation scattering. Use when building terrain generators, open-world
  environments, landscape visualizers, flight simulators, or any 3D scene requiring
  procedural ground surfaces. Triggers: "procedural terrain", "landscape generator",
  "heightmap", "terrain mesh", "procedural world", "open world", "terrain LOD",
  "terrain chunks", "noise terrain", "3D landscape".
---

# Procedural Landscapes

Generate performant, visually rich procedural terrain in Three.js with a WebGPU-first
architecture and automatic WebGL2 fallback.

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                  Renderer Init                   │
│  WebGPU available? ──yes──► WebGPURenderer       │
│         │no                                      │
│         └──────────────► WebGLRenderer            │
├─────────────────────────────────────────────────┤
│              Terrain Pipeline                    │
│  1. Noise Generation (GPU compute or CPU)        │
│  2. Heightmap → Geometry (chunked grid)          │
│  3. Normal Computation (per-vertex)              │
│  4. Material Assignment (slope + height rules)   │
│  5. LOD Management (camera-distance based)       │
├─────────────────────────────────────────────────┤
│              Environment Layers                  │
│  Water plane ─ Sky dome ─ Fog ─ Vegetation       │
└─────────────────────────────────────────────────┘
```

## Renderer Setup with Dual Backend

Always attempt WebGPU first, fall back to WebGL2 gracefully.

```javascript
import * as THREE from 'three';
import WebGPU from 'three/addons/capabilities/WebGPU.js';
import WebGPURenderer from 'three/addons/renderers/webgpu/WebGPURenderer.js';

async function createRenderer(canvas) {
  let renderer;
  let gpuAvailable = false;

  if (WebGPU.isAvailable()) {
    renderer = new WebGPURenderer({ canvas, antialias: true });
    await renderer.init();
    gpuAvailable = true;
  } else {
    renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.0;
  }

  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

  return { renderer, gpuAvailable };
}
```

**CDN usage (r170+)**:
```html
<script type="importmap">
{
  "imports": {
    "three": "https://cdn.jsdelivr.net/npm/three@0.170.0/build/three.module.js",
    "three/addons/": "https://cdn.jsdelivr.net/npm/three@0.170.0/examples/jsm/"
  }
}
</script>
```

## Noise Generation

### CPU Path (WebGL fallback)

Implement FBM noise on CPU when GPU compute is unavailable. Self-contained simplex noise
avoids external dependencies.

```javascript
function createNoise2D(seed = 0) {
  const perm = new Uint8Array(512);
  let s = seed;
  for (let i = 0; i < 256; i++) {
    s = (s * 16807 + 0) % 2147483647;
    perm[i] = perm[i + 256] = s & 255;
  }

  const G2 = (3 - Math.sqrt(3)) / 6;
  const grad = [[1,1],[-1,1],[1,-1],[-1,-1],[1,0],[-1,0],[0,1],[0,-1]];

  return function(x, y) {
    const s0 = (x + y) * 0.5 * (Math.sqrt(3) - 1);
    const i = Math.floor(x + s0), j = Math.floor(y + s0);
    const t0 = (i + j) * G2;
    const x0 = x - (i - t0), y0 = y - (j - t0);
    const i1 = x0 > y0 ? 1 : 0, j1 = x0 > y0 ? 0 : 1;
    const x1 = x0 - i1 + G2, y1 = y0 - j1 + G2;
    const x2 = x0 - 1 + 2 * G2, y2 = y0 - 1 + 2 * G2;
    const ii = i & 255, jj = j & 255;

    let n0 = 0, n1 = 0, n2 = 0;
    let t = 0.5 - x0*x0 - y0*y0;
    if (t > 0) { const g = grad[perm[ii + perm[jj]] & 7]; n0 = t*t*t*t * (g[0]*x0 + g[1]*y0); }
    t = 0.5 - x1*x1 - y1*y1;
    if (t > 0) { const g = grad[perm[ii+i1 + perm[jj+j1]] & 7]; n1 = t*t*t*t * (g[0]*x1 + g[1]*y1); }
    t = 0.5 - x2*x2 - y2*y2;
    if (t > 0) { const g = grad[perm[ii+1 + perm[jj+1]] & 7]; n2 = t*t*t*t * (g[0]*x2 + g[1]*y2); }
    return 70 * (n0 + n1 + n2);
  };
}
```

### FBM and Terrain Noise Functions

```javascript
function fbm(noise, x, y, octaves = 6, lacunarity = 2.0, gain = 0.5) {
  let sum = 0, amp = 1, freq = 1, maxAmp = 0;
  for (let i = 0; i < octaves; i++) {
    sum += noise(x * freq, y * freq) * amp;
    maxAmp += amp;
    amp *= gain;
    freq *= lacunarity;
  }
  return sum / maxAmp;
}

function ridgedMultifractal(noise, x, y, octaves = 6, lacunarity = 2.0, gain = 0.5) {
  let sum = 0, amp = 1, freq = 1, prev = 1;
  for (let i = 0; i < octaves; i++) {
    let n = 1 - Math.abs(noise(x * freq, y * freq));
    n = n * n * prev;
    sum += n * amp;
    prev = n;
    amp *= gain;
    freq *= lacunarity;
  }
  return sum;
}

function domainWarp(noise, x, y, strength = 0.3) {
  const qx = fbm(noise, x, y, 4);
  const qy = fbm(noise, x + 5.2, y + 1.3, 4);
  return fbm(noise, x + strength * qx, y + strength * qy, 6);
}
```

### GPU Compute Path (WebGPU)

For GPU-accelerated heightmap generation via WGSL compute shaders, see
`references/wgsl-shaders.md`. The compute path generates a heightmap texture
on the GPU, then samples it in vertex shaders or reads it back for collision.

## Terrain Geometry

### Single-Chunk Terrain

```javascript
function createTerrainGeometry(size, segments, heightFn, maxHeight = 50) {
  const geometry = new THREE.PlaneGeometry(size, size, segments, segments);
  geometry.rotateX(-Math.PI / 2);

  const position = geometry.attributes.position;
  const vertex = new THREE.Vector3();

  for (let i = 0; i < position.count; i++) {
    vertex.fromBufferAttribute(position, i);
    const nx = vertex.x / size + 0.5;
    const nz = vertex.z / size + 0.5;
    position.setY(i, heightFn(nx, nz) * maxHeight);
  }

  geometry.computeVertexNormals();
  position.needsUpdate = true;
  return geometry;
}
```

### Chunked Terrain with LOD

For larger worlds, divide terrain into chunks with distance-based LOD.

```javascript
class TerrainChunkManager {
  constructor(scene, chunkSize, viewDistance, heightFn, maxHeight) {
    this.scene = scene;
    this.chunkSize = chunkSize;
    this.viewDistance = viewDistance;
    this.heightFn = heightFn;
    this.maxHeight = maxHeight;
    this.chunks = new Map();
    this.lodLevels = [
      { distance: chunkSize * 2, segments: 64 },
      { distance: chunkSize * 5, segments: 32 },
      { distance: chunkSize * 10, segments: 16 },
      { distance: Infinity, segments: 8 },
    ];
  }

  update(cameraPosition) {
    const cx = Math.floor(cameraPosition.x / this.chunkSize);
    const cz = Math.floor(cameraPosition.z / this.chunkSize);
    const radius = Math.ceil(this.viewDistance / this.chunkSize);
    const activeKeys = new Set();

    for (let x = cx - radius; x <= cx + radius; x++) {
      for (let z = cz - radius; z <= cz + radius; z++) {
        const key = `${x},${z}`;
        activeKeys.add(key);
        const worldX = x * this.chunkSize;
        const worldZ = z * this.chunkSize;
        const dist = Math.hypot(cameraPosition.x - worldX, cameraPosition.z - worldZ);
        if (dist > this.viewDistance) continue;

        const lod = this.lodLevels.find(l => dist < l.distance);
        const existing = this.chunks.get(key);

        if (!existing || existing.lod !== lod.segments) {
          if (existing) { this.scene.remove(existing.mesh); existing.mesh.geometry.dispose(); }
          const mesh = this._createChunk(x, z, lod.segments);
          this.chunks.set(key, { mesh, lod: lod.segments });
          this.scene.add(mesh);
        }
      }
    }
    for (const [key, chunk] of this.chunks) {
      if (!activeKeys.has(key)) {
        this.scene.remove(chunk.mesh);
        chunk.mesh.geometry.dispose();
        this.chunks.delete(key);
      }
    }
  }

  _createChunk(cx, cz, segments) {
    const geo = createTerrainGeometry(
      this.chunkSize, segments,
      (nx, nz) => {
        const wx = (cx + nx) * this.chunkSize / 500;
        const wz = (cz + nz) * this.chunkSize / 500;
        return this.heightFn(wx, wz);
      },
      this.maxHeight
    );
    const mesh = new THREE.Mesh(geo, createTerrainMaterial());
    mesh.position.set(cx * this.chunkSize, 0, cz * this.chunkSize);
    mesh.receiveShadow = true;
    return mesh;
  }

  dispose() {
    for (const [, chunk] of this.chunks) {
      this.scene.remove(chunk.mesh);
      chunk.mesh.geometry.dispose();
    }
    this.chunks.clear();
  }
}
```

## Terrain Materials

### Slope + Height Shader (WebGL)

```javascript
function createTerrainMaterial() {
  return new THREE.ShaderMaterial({
    uniforms: {
      waterLevel:  { value: 0.05 },
      snowLevel:   { value: 0.75 },
      grassColor:  { value: new THREE.Color(0x4a7c3f) },
      rockColor:   { value: new THREE.Color(0x8b8680) },
      sandColor:   { value: new THREE.Color(0xc2b280) },
      snowColor:   { value: new THREE.Color(0xf0f0f5) },
      sunDir:      { value: new THREE.Vector3(0.5, 0.8, 0.3).normalize() },
      maxHeight:   { value: 50.0 },
    },
    vertexShader: `
      varying vec3 vWorldPos;
      varying vec3 vNormal;
      void main() {
        vWorldPos = (modelMatrix * vec4(position, 1.0)).xyz;
        vNormal = normalize(normalMatrix * normal);
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: `
      uniform float waterLevel, snowLevel, maxHeight;
      uniform vec3 grassColor, rockColor, sandColor, snowColor, sunDir;
      varying vec3 vWorldPos;
      varying vec3 vNormal;
      void main() {
        float h = clamp(vWorldPos.y / maxHeight, 0.0, 1.0);
        float slope = 1.0 - dot(vNormal, vec3(0, 1, 0));
        vec3 color = grassColor;
        if (h < waterLevel + 0.05)
          color = mix(sandColor, grassColor, smoothstep(waterLevel, waterLevel + 0.05, h));
        if (h > snowLevel)
          color = mix(color, snowColor, smoothstep(snowLevel, snowLevel + 0.1, h));
        color = mix(color, rockColor, smoothstep(0.3, 0.6, slope));
        float light = max(dot(vNormal, sunDir), 0.0) * 0.7 + 0.3;
        gl_FragColor = vec4(color * light, 1.0);
      }
    `,
  });
}
```

### Node Material (WebGPU TSL)

When using WebGPURenderer, prefer Three.js Shading Language (TSL) node materials:

```javascript
import { color, normalWorld, positionWorld, mix, smoothstep,
         dot, vec3, float as tslFloat, MeshStandardNodeMaterial } from 'three/tsl';

function createTerrainNodeMaterial(maxHeight = 50) {
  const material = new MeshStandardNodeMaterial();
  const h = positionWorld.y.div(tslFloat(maxHeight)).clamp(0, 1);
  const slope = tslFloat(1).sub(dot(normalWorld, vec3(0, 1, 0)));

  const grass = color(0x4a7c3f);
  const rock  = color(0x8b8680);
  const sand  = color(0xc2b280);
  const snow  = color(0xf0f0f5);

  let c = mix(sand, grass, smoothstep(0.0, 0.1, h));
  c = mix(c, snow, smoothstep(0.75, 0.85, h));
  c = mix(c, rock, smoothstep(0.3, 0.6, slope));

  material.colorNode = c;
  material.roughnessNode = mix(tslFloat(0.9), tslFloat(0.5), slope);
  return material;
}
```

## Water

```javascript
function createWater(size, waterLevel = 2.5) {
  const geometry = new THREE.PlaneGeometry(size, size, 128, 128);
  geometry.rotateX(-Math.PI / 2);
  const material = new THREE.MeshPhysicalMaterial({
    color: 0x006994, transparent: true, opacity: 0.7,
    roughness: 0.1, metalness: 0.1, transmission: 0.3, thickness: 2.0,
  });
  const water = new THREE.Mesh(geometry, material);
  water.position.y = waterLevel;

  water.userData.animate = (time) => {
    const pos = geometry.attributes.position;
    for (let i = 0; i < pos.count; i++) {
      const x = pos.getX(i), z = pos.getZ(i);
      pos.setY(i, Math.sin(x * 0.05 + time) * 0.3 + Math.cos(z * 0.08 + time * 0.7) * 0.2);
    }
    pos.needsUpdate = true;
    geometry.computeVertexNormals();
  };
  return water;
}
```

## Sky & Atmosphere

```javascript
function createSky() {
  const geo = new THREE.SphereGeometry(500, 32, 16);
  const mat = new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false,
    uniforms: {
      topColor:    { value: new THREE.Color(0x0077be) },
      bottomColor: { value: new THREE.Color(0xffeebb) },
      sunDir:      { value: new THREE.Vector3(0.3, 0.5, 0.4).normalize() },
    },
    vertexShader: `
      varying vec3 vDir;
      void main() {
        vDir = normalize(position);
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: `
      uniform vec3 topColor, bottomColor, sunDir;
      varying vec3 vDir;
      void main() {
        float y = vDir.y * 0.5 + 0.5;
        vec3 sky = mix(bottomColor, topColor, pow(y, 0.6));
        float sun = smoothstep(0.97, 1.0, dot(vDir, sunDir));
        sky += vec3(1.0, 0.95, 0.8) * sun * 0.8;
        gl_FragColor = vec4(sky, 1.0);
      }
    `,
  });
  return new THREE.Mesh(geo, mat);
}
```

## Vegetation Scattering

Place instanced vegetation using height and slope constraints.

```javascript
function scatterVegetation(heightFn, terrainSize, maxHeight, count = 5000) {
  const trunkGeo = new THREE.CylinderGeometry(0.1, 0.15, 1.5, 6);
  const canopyGeo = new THREE.ConeGeometry(0.8, 2.0, 6);
  canopyGeo.translate(0, 2.0, 0);
  const merged = mergeBufferGeometries(trunkGeo, canopyGeo);
  const material = new THREE.MeshStandardMaterial({ color: 0x2d5a27, flatShading: true });
  const mesh = new THREE.InstancedMesh(merged, material, count);
  mesh.castShadow = true;

  const dummy = new THREE.Object3D();
  const noise = createNoise2D(42);
  let placed = 0;

  for (let i = 0; i < count * 3 && placed < count; i++) {
    const x = (Math.random() - 0.5) * terrainSize;
    const z = (Math.random() - 0.5) * terrainSize;
    const h = heightFn(x / terrainSize + 0.5, z / terrainSize + 0.5) * maxHeight;
    const nh = h / maxHeight;
    if (nh < 0.08 || nh > 0.65) continue;
    if (noise(x * 0.01, z * 0.01) < 0.0) continue;

    dummy.position.set(x, h, z);
    dummy.rotation.y = Math.random() * Math.PI * 2;
    dummy.scale.setScalar(0.5 + Math.random());
    dummy.updateMatrix();
    mesh.setMatrixAt(placed++, dummy.matrix);
  }

  mesh.count = placed;
  mesh.instanceMatrix.needsUpdate = true;
  return mesh;
}

function mergeBufferGeometries(a, b) {
  const na = a.toNonIndexed(), nb = b.toNonIndexed();
  const pA = na.attributes.position.array, pB = nb.attributes.position.array;
  const nA = na.attributes.normal.array, nB = nb.attributes.normal.array;
  const pos = new Float32Array(pA.length + pB.length);
  const nor = new Float32Array(nA.length + nB.length);
  pos.set(pA); pos.set(pB, pA.length);
  nor.set(nA); nor.set(nB, nA.length);
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  geo.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  return geo;
}
```

## Performance Guidelines

- **Geometry budget**: 64×64 for distant chunks, 256×256 for close. Never exceed 512×512.
- **Instanced rendering**: Always use `InstancedMesh` for repeated objects. One draw call for 10K instances beats 10K meshes by ~100×.
- **Dispose aggressively**: `.dispose()` geometry, materials, textures when removing chunks.
- **Shadow optimization**: One shadow-casting directional light. Use `CSM` addon for large terrains.
- **Vertex totals**: Mobile < 500K, Desktop < 2M across visible scene.
- **WebGPU compute**: 10–50× faster than CPU for 1024² heightmaps. Use for real-time sculpting.

## Noise Selection Guide

| Noise Type | Character | Best For |
|---|---|---|
| FBM | Smooth rolling hills | Meadows, plains |
| Ridged Multifractal | Sharp ridges/valleys | Mountains, canyons |
| Domain Warping | Organic twisted forms | Fantasy, alien terrain |
| Terraced FBM | Stepped plateaus | Mesas, rice paddies |

**Combine multiplicatively** for complex terrain:
```javascript
function complexTerrain(noise, x, y) {
  const base = fbm(noise, x * 0.5, y * 0.5, 4) * 0.5 + 0.5;
  const mountains = ridgedMultifractal(noise, x, y, 6) * 0.4;
  const detail = domainWarp(noise, x * 2, y * 2, 0.2) * 0.1;
  return Math.max(base * 0.5 + mountains * base + detail, 0);
}
```

## Common Pitfalls

1. **Normals not recomputed** after vertex modification → flat/unlit terrain. Always call `geometry.computeVertexNormals()`.
2. **Chunk seams** → sample identical world-space noise at shared edges.
3. **Z-fighting on water** → use `polygonOffset` or small Y offset.
4. **Memory leaks** → dispose geometries on chunk removal. Monitor with `renderer.info`.
5. **WebGPU silent failure** → always gate behind `WebGPU.isAvailable()`.

## References

- `references/wgsl-shaders.md` — Complete WGSL compute shaders for GPU heightmap generation, erosion simulation, and normal computation.
- `references/noise-algorithms.md` — Mathematical foundations and advanced noise variants (Voronoi, analytical derivatives, curl noise).

---

<!-- file: noise-algorithms.md -->

# Noise Algorithms Reference

Mathematical foundations and advanced noise variants for procedural terrain generation.

## Core Concepts

### Frequency, Amplitude, and Octaves

Procedural noise is built by layering frequencies:

- **Frequency**: How "zoomed in" the noise is. Higher = more detail, smaller features.
- **Amplitude**: How much influence each layer has on the final value.
- **Octave**: A single noise layer at a specific frequency/amplitude.
- **Lacunarity**: Frequency multiplier between octaves (typically 2.0).
- **Persistence/Gain**: Amplitude multiplier between octaves (typically 0.5).

Standard FBM stacks 4–8 octaves. More octaves = more fine detail but diminishing returns past 8.

### Value Range Normalization

Raw FBM output ranges approximately `[-1, 1]`. For terrain height, remap to `[0, 1]`:

```javascript
const normalized = fbm(...) * 0.5 + 0.5;
```

For ridged noise, output is `[0, ~2]` depending on octaves. Divide by peak theoretical value or clamp.

## Advanced Noise Variants

### Terraced Noise

Creates stepped, plateau-like terrain (mesa formations, rice paddies).

```javascript
function terraced(noise, x, y, steps = 8) {
  const n = fbm(noise, x, y, 6) * 0.5 + 0.5;
  return Math.round(n * steps) / steps;
}

// Smooth terrace edges with interpolation
function smoothTerraced(noise, x, y, steps = 8, sharpness = 4) {
  const n = fbm(noise, x, y, 6) * 0.5 + 0.5;
  const stepped = Math.round(n * steps) / steps;
  const frac = (n * steps) % 1;
  const smooth = 1 / (1 + Math.exp(-sharpness * (frac - 0.5)));
  return stepped + smooth / steps;
}
```

### Voronoi / Worley Noise

Cellular noise producing patterns resembling cracked earth, stone tiles, or organic cells.

```javascript
function voronoi(x, y) {
  const ix = Math.floor(x), iy = Math.floor(y);
  const fx = x - ix, fy = y - iy;
  let minDist = Infinity;
  let secondDist = Infinity;

  for (let dy = -1; dy <= 1; dy++) {
    for (let dx = -1; dx <= 1; dx++) {
      // Deterministic random point per cell
      const cx = ix + dx, cy = iy + dy;
      const h = Math.sin(cx * 127.1 + cy * 311.7) * 43758.5453;
      const px = dx + (h - Math.floor(h)) - fx;
      const py = dy + (Math.sin(cx * 269.5 + cy * 183.3) * 43758.5453 % 1) - fy;

      const dist = px * px + py * py;
      if (dist < minDist) {
        secondDist = minDist;
        minDist = dist;
      } else if (dist < secondDist) {
        secondDist = dist;
      }
    }
  }

  return {
    f1: Math.sqrt(minDist),           // Distance to closest point
    f2: Math.sqrt(secondDist),        // Distance to second closest
    edge: Math.sqrt(secondDist) - Math.sqrt(minDist), // Edge detection
  };
}

// Use f2 - f1 for cracks/ridges, f1 for cells
function voronoiTerrain(noise, x, y, scale = 2) {
  const v = voronoi(x * scale, y * scale);
  const base = fbm(noise, x, y, 4) * 0.5 + 0.5;
  return base * 0.7 + v.f1 * 0.3; // Cellular rocky terrain
}
```

### Analytical Derivatives

Compute noise derivatives alongside values for slope-aware operations (erosion direction,
normal computation) without finite differences.

```javascript
// Returns { value, dx, dy } - the noise value and its partial derivatives
function fbmWithDerivatives(noise, x, y, octaves = 6, lac = 2.0, gain = 0.5) {
  let sum = 0, dx = 0, dy = 0;
  let amp = 1, freq = 1, maxAmp = 0;
  const eps = 0.001;

  for (let i = 0; i < octaves; i++) {
    const nx = x * freq, ny = y * freq;
    const v = noise(nx, ny);
    // Finite difference approximation of derivatives
    const vx = noise(nx + eps, ny);
    const vy = noise(nx, ny + eps);

    sum += v * amp;
    dx += ((vx - v) / eps) * amp * freq;
    dy += ((vy - v) / eps) * amp * freq;
    maxAmp += amp;
    amp *= gain;
    freq *= lac;
  }
  return { value: sum / maxAmp, dx: dx / maxAmp, dy: dy / maxAmp };
}
```

### Curl Noise (2D)

Divergence-free noise field useful for wind patterns, water flow visualization, and
particle advection over terrain.

```javascript
function curlNoise2D(noise, x, y, eps = 0.01) {
  // Curl of a 2D scalar field gives a 2D vector
  const dndx = (noise(x + eps, y) - noise(x - eps, y)) / (2 * eps);
  const dndy = (noise(x, y + eps) - noise(x, y - eps)) / (2 * eps);
  // Rotate 90 degrees for divergence-free field
  return { x: dndy, y: -dndx };
}

// Use for river path generation
function traceFlowPath(noise, startX, startY, steps = 200, stepSize = 0.5) {
  const path = [{ x: startX, y: startY }];
  let x = startX, y = startY;

  for (let i = 0; i < steps; i++) {
    const flow = curlNoise2D(noise, x * 0.1, y * 0.1);
    x += flow.x * stepSize;
    y += flow.y * stepSize;
    path.push({ x, y });
  }
  return path;
}
```

### Billowed Noise

Soft, cloud-like variant. Absolute value of FBM creates pillow-shaped undulations.

```javascript
function billowed(noise, x, y, octaves = 6) {
  let sum = 0, amp = 1, freq = 1, maxAmp = 0;
  for (let i = 0; i < octaves; i++) {
    sum += Math.abs(noise(x * freq, y * freq)) * amp;
    maxAmp += amp;
    amp *= 0.5;
    freq *= 2.0;
  }
  return sum / maxAmp;
}
```

## Terrain Composition Recipes

### Island with Ocean Falloff

```javascript
function islandTerrain(noise, x, y, islandRadius = 0.4) {
  const cx = x - 0.5, cy = y - 0.5;
  const dist = Math.sqrt(cx * cx + cy * cy);
  const falloff = Math.max(0, 1 - Math.pow(dist / islandRadius, 2));

  const height = domainWarp(noise, x * 3, y * 3, 0.4) * 0.5 + 0.5;
  return height * falloff * falloff; // Squared falloff for smooth coastline
}
```

### Mountain Range with Foothills

```javascript
function mountainRange(noise, x, y) {
  // Directional ridge along x-axis
  const ridgeLine = Math.exp(-y * y * 8); // Gaussian ridge mask
  const peaks = ridgedMultifractal(noise, x * 2, y * 2, 6) * ridgeLine;
  const foothills = fbm(noise, x, y, 4) * 0.5 + 0.5;
  return foothills * 0.3 + peaks * 0.7;
}
```

### Erosion-Like Channels (CPU approximation)

```javascript
function erodedTerrain(noise, x, y, iterations = 3) {
  let h = fbm(noise, x, y, 6) * 0.5 + 0.5;
  for (let i = 0; i < iterations; i++) {
    // Carve channels following steepest descent
    const { dx, dy } = fbmWithDerivatives(noise, x * (1 + i * 0.5), y * (1 + i * 0.5), 4);
    const slope = Math.sqrt(dx * dx + dy * dy);
    h -= slope * 0.05 * (1 / (i + 1)); // Diminishing erosion per pass
  }
  return Math.max(h, 0);
}
```

## Seed Management

Consistent seeding enables reproducible terrain for multiplayer or save/load.

```javascript
// Create deterministic noise instances for different layers
function createSeededLayers(worldSeed) {
  return {
    elevation: createNoise2D(worldSeed),
    moisture:  createNoise2D(worldSeed + 1),
    temperature: createNoise2D(worldSeed + 2),
    detail:    createNoise2D(worldSeed + 3),
    vegetation: createNoise2D(worldSeed + 4),
  };
}

// Each layer uses different frequency ranges for independent variation
function sampleBiomeData(layers, x, y) {
  return {
    height: fbm(layers.elevation, x, y, 6),
    moisture: fbm(layers.moisture, x * 0.7, y * 0.7, 4) * 0.5 + 0.5,
    temperature: fbm(layers.temperature, x * 0.3, y * 0.3, 3) * 0.5 + 0.5,
  };
}
```

## Performance Considerations

- **CPU noise at 256×256**: ~5–15ms. Acceptable for single chunks on load.
- **CPU noise at 1024×1024**: ~100–300ms. Use web workers or GPU compute.
- **GPU compute at 1024×1024**: ~1–5ms. Essential for real-time modification.
- **Octave count**: Diminishing visual returns past 6 octaves. Use 4 for distant LOD.
- **Cache heightmaps**: Store computed heights in `Float32Array` for physics/collision queries rather than recomputing per frame.

---

<!-- file: wgsl-shaders.md -->

# WGSL Shaders for Procedural Terrain

Complete WebGPU Shading Language (WGSL) implementations for GPU-accelerated terrain
generation. Use with Three.js r170+ WebGPURenderer and TSL compute nodes.

## Heightmap Compute Shader

Generate a heightmap texture entirely on the GPU using FBM noise in a compute shader.

### Three.js TSL Compute Setup

```javascript
import { compute, storageTexture, textureStore, uvec2, vec2, float as tslFloat,
         instanceIndex, textureSize } from 'three/tsl';

function createHeightmapCompute(resolution = 512) {
  const heightmap = new THREE.StorageTexture(resolution, resolution);
  heightmap.type = THREE.FloatType;

  // Compute kernel: one thread per texel
  const computeFn = Fn(() => {
    const idx = instanceIndex;
    const size = textureSize(storageTexture(heightmap));
    const x = idx.modInt(size.x);
    const y = idx.div(size.x);
    const uv = vec2(x, y).div(vec2(size));

    // FBM noise in TSL
    const height = tslFbm(uv, 6);
    textureStore(storageTexture(heightmap), uvec2(x, y), vec4(height, 0, 0, 1));
  });

  const computeNode = compute(computeFn, [resolution * resolution]);
  return { heightmap, computeNode };
}
```

### Raw WGSL Compute Shader

For direct WGSL usage or custom pipelines outside TSL:

```wgsl
// heightmap_compute.wgsl
@group(0) @binding(0) var output: texture_storage_2d<r32float, write>;

struct Params {
  resolution: u32,
  scale: f32,
  octaves: u32,
  lacunarity: f32,
  gain: f32,
  seed: f32,
  offset_x: f32,
  offset_z: f32,
}
@group(0) @binding(1) var<uniform> params: Params;

// Permutation-free gradient noise (no lookup table needed on GPU)
fn hash2(p: vec2<f32>) -> vec2<f32> {
  var q = vec2<f32>(
    dot(p, vec2<f32>(127.1, 311.7)),
    dot(p, vec2<f32>(269.5, 183.3))
  );
  return fract(sin(q) * 43758.5453) * 2.0 - 1.0;
}

fn gradientNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f); // Hermite interpolation

  let a = dot(hash2(i + vec2<f32>(0.0, 0.0)), f - vec2<f32>(0.0, 0.0));
  let b = dot(hash2(i + vec2<f32>(1.0, 0.0)), f - vec2<f32>(1.0, 0.0));
  let c = dot(hash2(i + vec2<f32>(0.0, 1.0)), f - vec2<f32>(0.0, 1.0));
  let d = dot(hash2(i + vec2<f32>(1.0, 1.0)), f - vec2<f32>(1.0, 1.0));

  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: u32, lac: f32, gain: f32) -> f32 {
  var sum = 0.0;
  var amp = 1.0;
  var freq = 1.0;
  var maxAmp = 0.0;
  var pos = p;

  for (var i = 0u; i < octaves; i++) {
    sum += gradientNoise(pos * freq) * amp;
    maxAmp += amp;
    amp *= gain;
    freq *= lac;
  }
  return sum / maxAmp;
}

fn ridged(p: vec2<f32>, octaves: u32, lac: f32, gain: f32) -> f32 {
  var sum = 0.0;
  var amp = 1.0;
  var freq = 1.0;
  var prev = 1.0;

  for (var i = 0u; i < octaves; i++) {
    var n = 1.0 - abs(gradientNoise(p * freq));
    n = n * n * prev;
    sum += n * amp;
    prev = n;
    amp *= gain;
    freq *= lac;
  }
  return sum;
}

fn domainWarp(p: vec2<f32>, strength: f32) -> f32 {
  let qx = fbm(p, 4u, 2.0, 0.5);
  let qy = fbm(p + vec2<f32>(5.2, 1.3), 4u, 2.0, 0.5);
  return fbm(p + strength * vec2<f32>(qx, qy), 6u, 2.0, 0.5);
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = params.resolution;
  if (gid.x >= res || gid.y >= res) { return; }

  let uv = vec2<f32>(f32(gid.x), f32(gid.y)) / f32(res);
  let worldPos = (uv - 0.5) * params.scale + vec2<f32>(params.offset_x, params.offset_z);

  // Combine noise layers
  let base = fbm(worldPos * 0.5, params.octaves, params.lacunarity, params.gain) * 0.5 + 0.5;
  let mountains = ridged(worldPos, params.octaves, params.lacunarity, params.gain) * 0.4;
  let warp = domainWarp(worldPos, 0.4) * 0.1;

  let height = max(base * 0.5 + mountains * base + warp, 0.0);

  textureStore(output, vec2<u32>(gid.x, gid.y), vec4<f32>(height, 0.0, 0.0, 1.0));
}
```

### Binding the Compute Pipeline in Three.js

```javascript
// Manual WebGPU compute pipeline (when TSL abstractions aren't sufficient)
async function runHeightmapCompute(renderer, resolution, params) {
  const device = renderer.backend.device;

  // Create storage texture
  const texture = device.createTexture({
    size: [resolution, resolution],
    format: 'r32float',
    usage: GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.TEXTURE_BINDING,
  });

  // Create uniform buffer
  const uniformData = new ArrayBuffer(32);
  const view = new DataView(uniformData);
  view.setUint32(0, resolution, true);
  view.setFloat32(4, params.scale ?? 4.0, true);
  view.setUint32(8, params.octaves ?? 6, true);
  view.setFloat32(12, params.lacunarity ?? 2.0, true);
  view.setFloat32(16, params.gain ?? 0.5, true);
  view.setFloat32(20, params.seed ?? 0.0, true);
  view.setFloat32(24, params.offsetX ?? 0.0, true);
  view.setFloat32(28, params.offsetZ ?? 0.0, true);

  const uniformBuffer = device.createBuffer({
    size: uniformData.byteLength,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });
  device.queue.writeBuffer(uniformBuffer, 0, uniformData);

  // Dispatch
  const workgroups = Math.ceil(resolution / 16);
  // ... create pipeline, bind group, dispatch, read back texture
  return texture;
}
```

## Normal Computation Shader

Compute normals from a heightmap texture on the GPU for smooth lighting.

```wgsl
// normals_compute.wgsl
@group(0) @binding(0) var heightmap: texture_2d<f32>;
@group(0) @binding(1) var output: texture_storage_2d<rgba8snorm, write>;

struct Params { resolution: u32, heightScale: f32, texelSize: f32 }
@group(0) @binding(2) var<uniform> params: Params;

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = params.resolution;
  if (gid.x >= res || gid.y >= res) { return; }

  let x = i32(gid.x);
  let y = i32(gid.y);

  // Sample neighbors (clamped at edges)
  let hL = textureLoad(heightmap, vec2<i32>(max(x - 1, 0), y), 0).r;
  let hR = textureLoad(heightmap, vec2<i32>(min(x + 1, i32(res) - 1), y), 0).r;
  let hD = textureLoad(heightmap, vec2<i32>(x, max(y - 1, 0)), 0).r;
  let hU = textureLoad(heightmap, vec2<i32>(x, min(y + 1, i32(res) - 1)), 0).r;

  let scale = params.heightScale * params.texelSize;
  let normal = normalize(vec3<f32>(
    (hL - hR) * scale,
    2.0,
    (hD - hU) * scale
  ));

  textureStore(output, vec2<u32>(gid.xy), vec4<f32>(normal, 1.0));
}
```

## Hydraulic Erosion Compute Shader

Simulate water erosion on the heightmap for realistic terrain features.

```wgsl
// erosion_compute.wgsl
@group(0) @binding(0) var heightmap: texture_storage_2d<r32float, read_write>;

struct ErosionParams {
  resolution: u32,
  droplets: u32,
  inertia: f32,
  capacity: f32,
  deposition: f32,
  erosion: f32,
  evaporation: f32,
  gravity: f32,
  maxSteps: u32,
  _pad: u32,
}
@group(0) @binding(1) var<uniform> params: ErosionParams;

fn sampleHeight(pos: vec2<f32>, res: u32) -> f32 {
  let p = clamp(pos, vec2<f32>(0.0), vec2<f32>(f32(res) - 1.0));
  let ip = vec2<u32>(u32(p.x), u32(p.y));
  return textureLoad(heightmap, ip).r;
}

fn calcGradient(pos: vec2<f32>, res: u32) -> vec2<f32> {
  let eps = 1.0;
  let hL = sampleHeight(pos - vec2<f32>(eps, 0.0), res);
  let hR = sampleHeight(pos + vec2<f32>(eps, 0.0), res);
  let hD = sampleHeight(pos - vec2<f32>(0.0, eps), res);
  let hU = sampleHeight(pos + vec2<f32>(0.0, eps), res);
  return vec2<f32>(hR - hL, hU - hD) * 0.5;
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  if (gid.x >= params.droplets) { return; }

  let res = params.resolution;
  // Pseudo-random starting position using thread ID
  let seed = f32(gid.x) * 0.618033988749;
  var pos = vec2<f32>(fract(seed * 127.1) * f32(res), fract(seed * 311.7) * f32(res));
  var dir = vec2<f32>(0.0);
  var speed = 1.0;
  var water = 1.0;
  var sediment = 0.0;

  for (var step = 0u; step < params.maxSteps; step++) {
    let grad = calcGradient(pos, res);
    dir = dir * params.inertia - grad * (1.0 - params.inertia);

    if (length(dir) < 0.0001) { break; }
    dir = normalize(dir);

    let oldH = sampleHeight(pos, res);
    pos += dir;

    if (pos.x < 0.0 || pos.x >= f32(res) || pos.y < 0.0 || pos.y >= f32(res)) { break; }

    let newH = sampleHeight(pos, res);
    let dH = newH - oldH;

    let cap = max(-dH * speed * water * params.capacity, 0.01);

    if (sediment > cap || dH > 0.0) {
      let deposit = select((sediment - cap) * params.deposition, min(dH, sediment), dH > 0.0);
      sediment -= deposit;
      let ip = vec2<u32>(u32(pos.x), u32(pos.y));
      let h = textureLoad(heightmap, ip).r + deposit;
      textureStore(heightmap, ip, vec4<f32>(h, 0.0, 0.0, 1.0));
    } else {
      let erode = min((cap - sediment) * params.erosion, -dH);
      sediment += erode;
      let ip = vec2<u32>(u32(pos.x), u32(pos.y));
      let h = textureLoad(heightmap, ip).r - erode;
      textureStore(heightmap, ip, vec4<f32>(h, 0.0, 0.0, 1.0));
    }

    speed = sqrt(max(speed * speed + dH * params.gravity, 0.0));
    water *= (1.0 - params.evaporation);
  }
}
```

## Vertex Displacement Shader

Instead of modifying geometry on the CPU, displace vertices directly from the
heightmap texture in the vertex shader.

### GLSL (WebGL fallback)

```glsl
// terrain_displacement.vert
uniform sampler2D heightmap;
uniform float maxHeight;
uniform vec2 terrainOffset;
uniform float terrainScale;

varying vec3 vWorldPos;
varying vec3 vNormal;
varying vec2 vUv;

void main() {
  vUv = uv;
  vec2 samplePos = uv * terrainScale + terrainOffset;
  float h = texture2D(heightmap, samplePos).r * maxHeight;

  vec3 pos = position;
  pos.y += h;

  // Compute normal from heightmap neighbors
  float texel = 1.0 / 512.0; // Match heightmap resolution
  float hL = texture2D(heightmap, samplePos + vec2(-texel, 0.0)).r * maxHeight;
  float hR = texture2D(heightmap, samplePos + vec2( texel, 0.0)).r * maxHeight;
  float hD = texture2D(heightmap, samplePos + vec2(0.0, -texel)).r * maxHeight;
  float hU = texture2D(heightmap, samplePos + vec2(0.0,  texel)).r * maxHeight;

  vec3 computedNormal = normalize(vec3(hL - hR, 2.0, hD - hU));

  vWorldPos = (modelMatrix * vec4(pos, 1.0)).xyz;
  vNormal = normalize(normalMatrix * computedNormal);
  gl_Position = projectionMatrix * modelViewMatrix * vec4(pos, 1.0);
}
```

### TSL (WebGPU)

```javascript
import { texture, positionLocal, normalLocal, uniform, vec2, vec3,
         float as tslFloat, attribute } from 'three/tsl';

function createDisplacementMaterial(heightmapTex, maxHeight = 50) {
  const material = new MeshStandardNodeMaterial();
  const uv = attribute('uv');
  const h = texture(heightmapTex, uv).r.mul(tslFloat(maxHeight));

  // Displace Y
  material.positionNode = positionLocal.add(vec3(0, h, 0));

  // Compute normal from neighbors
  const texel = tslFloat(1.0 / 512.0);
  const hL = texture(heightmapTex, uv.add(vec2(texel.negate(), 0))).r.mul(tslFloat(maxHeight));
  const hR = texture(heightmapTex, uv.add(vec2(texel, 0))).r.mul(tslFloat(maxHeight));
  const hD = texture(heightmapTex, uv.add(vec2(0, texel.negate()))).r.mul(tslFloat(maxHeight));
  const hU = texture(heightmapTex, uv.add(vec2(0, texel))).r.mul(tslFloat(maxHeight));
  material.normalNode = normalize(vec3(hL.sub(hR), tslFloat(2), hD.sub(hU)));

  return material;
}
```

## Usage Tips

- **Dispatch workgroup sizes**: Use 16×16 for 2D texture ops, 64 or 256 for 1D arrays. Ensure dispatch count covers full resolution: `Math.ceil(resolution / 16)`.
- **Storage texture formats**: `r32float` for heightmaps, `rgba8snorm` for normals, `rgba8unorm` for color maps.
- **Read-back**: To read GPU heightmap data back to CPU (for collision), use `GPUBuffer` with `MAP_READ` usage and `copyTextureToBuffer`.
- **Erosion iterations**: Run 50K–200K droplets for visible results on 512×512. Multiple passes with `storageBarrier()` between them.

---

```text
MIT License

Copyright (c) 2026 CK42BB

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
