# CK42BB procedural-stars-threejs

From [procedural-stars-threejs](https://github.com/CK42BB/procedural-stars-threejs), Kingsley (CK42BB), commit `4c04e03`, MIT (notice at the end). Night sky in layers: sky dome, blackbody-coloured starfield with magnitude sizes and vertex twinkle, FBM Milky Way with dust lanes, billboard and raymarched nebulae (emission, absorption, reflection), moons with phases, meteors, comets, eclipses, plus a WGSL compute star catalogue. Teaching samples, not tested at Elsewhere's scales; read for ideas and port to TSL. Each original file follows unchanged.

---

<!-- file: SKILL.md -->

---
name: procedural-starfield
description: >
  Generate stunning procedural night skies, starfields, nebulae, and celestial phenomena
  in Three.js using WebGPU compute with WebGL2 fallback. Covers scientifically-grounded
  starfields with spectral color temperature, magnitude-based brightness, and twinkling;
  volumetric nebulae with emission/absorption/reflection types; the Milky Way band;
  constellations with optional line overlays; planets and moons with phase lighting;
  shooting stars and meteor showers; aurora integration; eclipses (solar and lunar);
  comets with ion/dust tails; galaxies as deep-sky backdrop objects; and a full
  sky dome controller with time-of-night progression, moon phases, and horizon glow.
  Triggers: "procedural starfield", "night sky", "star rendering", "nebula",
  "deep space", "milky way", "constellation", "shooting star", "meteor shower",
  "celestial", "space background", "starbox", "skybox stars", "galaxy background",
  "moon phases", "comet", "eclipse", "space scene", "star shader".
---

# Procedural Starfield & Celestial Phenomena

Generate breathtaking night skies in Three.js — from photorealistic starfields to
dreamy nebulae to dramatic celestial events.

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│               Night Sky Pipeline                      │
│                                                      │
│  SkyController (master orchestrator)                 │
│    ├── time progression (sunset → night → dawn)      │
│    ├── moon phase + position                         │
│    └── drives all layers:                            │
│                                                      │
│  ┌─ Layer 1: Sky Dome ──────────────────────────┐    │
│  │  Gradient background, horizon glow, zodiacal │    │
│  └──────────────────────────────────────────────┘    │
│  ┌─ Layer 2: Stars ─────────────────────────────┐    │
│  │  Points with spectral color + magnitude      │    │
│  │  Twinkle, proper motion (optional)           │    │
│  └──────────────────────────────────────────────┘    │
│  ┌─ Layer 3: Milky Way ─────────────────────────┐    │
│  │  Textured band or procedural FBM glow        │    │
│  └──────────────────────────────────────────────┘    │
│  ┌─ Layer 4: Nebulae ───────────────────────────┐    │
│  │  Volumetric raymarched or billboard sprites  │    │
│  └──────────────────────────────────────────────┘    │
│  ┌─ Layer 5: Celestial Bodies ──────────────────┐    │
│  │  Moon (phase lit), planets, sun glow         │    │
│  └──────────────────────────────────────────────┘    │
│  ┌─ Layer 6: Transients ────────────────────────┐    │
│  │  Shooting stars, comets, eclipses, satellites│    │
│  └──────────────────────────────────────────────┘    │
│  ┌─ Layer 7: Deep Space (optional) ─────────────┐    │
│  │  Distant galaxies, star clusters, dust lanes │    │
│  └──────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────┘
```

## Renderer Setup

```javascript
import * as THREE from 'three';

async function createRenderer(canvas) {
  let renderer, gpuAvailable = false;
  try {
    const WebGPU = (await import('three/addons/capabilities/WebGPU.js')).default;
    if (WebGPU.isAvailable()) {
      const { default: WebGPURenderer } = await import(
        'three/addons/renderers/webgpu/WebGPURenderer.js'
      );
      renderer = new WebGPURenderer({ canvas, antialias: true });
      await renderer.init();
      gpuAvailable = true;
    }
  } catch (e) {}
  if (!renderer) {
    renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.0;
  }
  renderer.setSize(innerWidth, innerHeight);
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  return { renderer, gpuAvailable };
}
```

## Layer 1: Sky Dome

Gradient hemisphere that transitions from deep zenith to warm horizon glow, with
optional light pollution and twilight blending.

```javascript
function createSkyDome(radius = 500) {
  const geo = new THREE.SphereGeometry(radius, 32, 16);
  const material = new THREE.ShaderMaterial({
    uniforms: {
      zenithColor:   { value: new THREE.Color(0x020010) },
      midColor:      { value: new THREE.Color(0x0a0a2a) },
      horizonColor:  { value: new THREE.Color(0x15102a) },
      horizonGlow:   { value: new THREE.Color(0x1a1530) },
      glowStrength:  { value: 0.3 },
      lightPollution: { value: 0.0 },  // 0=pristine, 1=urban
      moonPos:       { value: new THREE.Vector3(0, 0.5, -1).normalize() },
      moonGlowStr:   { value: 0.15 },
    },
    vertexShader: `
      varying vec3 vWorldDir;
      void main() {
        vec4 worldPos = modelMatrix * vec4(position, 1.0);
        vWorldDir = normalize(worldPos.xyz);
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: SKY_DOME_FRAG, // See references/celestial-shaders.md
    side: THREE.BackSide,
    depthWrite: false,
  });

  return new THREE.Mesh(geo, material);
}
```

## Layer 2: Starfield

The heart of the night sky. Each star is a `Points` particle with scientifically-
grounded color (spectral class → blackbody temperature), magnitude-based size/brightness,
and animated twinkle.

### Star Generation

```javascript
class Starfield {
  constructor(scene, options = {}) {
    this.scene = scene;
    this.count = options.count ?? 8000;
    this.radius = options.radius ?? 400;
    this.minMagnitude = options.minMagnitude ?? -1.5; // Brightest (Sirius)
    this.maxMagnitude = options.maxMagnitude ?? 6.5;  // Faintest visible
    this.twinkleSpeed = options.twinkleSpeed ?? 1.0;
    this.seed = options.seed ?? 42;

    this._build();
  }

  _build() {
    const positions = new Float32Array(this.count * 3);
    const starData = new Float32Array(this.count * 4); // r, g, b, magnitude

    let rng = this.seed;
    const random = () => { rng = (rng * 16807) % 2147483647; return rng / 2147483647; };

    for (let i = 0; i < this.count; i++) {
      // Uniform distribution on sphere
      const theta = random() * Math.PI * 2;
      const phi = Math.acos(2 * random() - 1);

      positions[i * 3]     = Math.sin(phi) * Math.cos(theta) * this.radius;
      positions[i * 3 + 1] = Math.sin(phi) * Math.sin(theta) * this.radius;
      positions[i * 3 + 2] = Math.cos(phi) * this.radius;

      // Magnitude: exponential distribution (many faint, few bright)
      const mag = this.minMagnitude + Math.pow(random(), 0.4) * (this.maxMagnitude - this.minMagnitude);

      // Spectral color from temperature
      const temp = this._randomStarTemp(random());
      const col = blackbodyColor(temp);

      starData[i * 4]     = col.r;
      starData[i * 4 + 1] = col.g;
      starData[i * 4 + 2] = col.b;
      starData[i * 4 + 3] = mag;
    }

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geometry.setAttribute('aStarData', new THREE.BufferAttribute(starData, 4));

    this.material = new THREE.ShaderMaterial({
      uniforms: {
        time:          { value: 0 },
        twinkleSpeed:  { value: this.twinkleSpeed },
        brightnessExp: { value: 2.5 },  // Magnitude → size exponent
        baseSizePx:    { value: 2.5 },
        glowFalloff:   { value: 0.4 },
        exposure:      { value: 1.0 },
      },
      vertexShader: STAR_VERT,     // See references/celestial-shaders.md
      fragmentShader: STAR_FRAG,   // See references/celestial-shaders.md
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    });

    this.mesh = new THREE.Points(geometry, this.material);
    this.mesh.frustumCulled = false;
    this.scene.add(this.mesh);
  }

  // Realistic star temperature distribution
  _randomStarTemp(r) {
    // Weighted toward cooler stars (M/K/G), fewer hot O/B
    if (r < 0.003)  return 30000 + r * 5000000;  // O: blue-white
    if (r < 0.01)   return 10000 + r * 1000000;   // B: blue
    if (r < 0.04)   return 7500 + r * 60000;      // A: white
    if (r < 0.11)   return 6000 + r * 15000;      // F: yellow-white
    if (r < 0.23)   return 5200 + r * 5000;       // G: yellow (Sun-like)
    if (r < 0.50)   return 3700 + r * 3000;       // K: orange
    return 2400 + r * 2600;                        // M: red
  }

  update(time) {
    this.material.uniforms.time.value = time;
  }

  dispose() {
    this.scene.remove(this.mesh);
    this.mesh.geometry.dispose();
    this.material.dispose();
  }
}
```

### Blackbody Color Function

Convert Kelvin temperature to RGB for accurate star colors:

```javascript
function blackbodyColor(tempK) {
  // Attempt a physically-grounded approximation (Tanner Helland algorithm)
  const t = tempK / 100;
  let r, g, b;

  if (t <= 66) {
    r = 255;
    g = 99.4708025861 * Math.log(t) - 161.1195681661;
    b = t <= 19 ? 0 : 138.5177312231 * Math.log(t - 10) - 305.0447927307;
  } else {
    r = 329.698727446 * Math.pow(t - 60, -0.1332047592);
    g = 288.1221695283 * Math.pow(t - 60, -0.0755148492);
    b = 255;
  }

  return new THREE.Color(
    Math.min(Math.max(r, 0), 255) / 255,
    Math.min(Math.max(g, 0), 255) / 255,
    Math.min(Math.max(b, 0), 255) / 255
  );
}
```

**Star spectral classes and their temperatures/colors:**

| Class | Temp (K) | Color | Fraction | Examples |
|-------|----------|-------|----------|----------|
| O | 30,000+ | Blue-violet | 0.003% | Mintaka |
| B | 10,000–30,000 | Blue-white | 0.1% | Rigel, Spica |
| A | 7,500–10,000 | White | 0.6% | Sirius, Vega |
| F | 6,000–7,500 | Yellow-white | 3% | Procyon |
| G | 5,200–6,000 | Yellow | 8% | Sun, Alpha Centauri |
| K | 3,700–5,200 | Orange | 12% | Arcturus |
| M | 2,400–3,700 | Red-orange | 76% | Betelgeuse, Proxima |

## Layer 3: Milky Way

A luminous band across the sky, rendered as a textured strip or procedural FBM glow
on the sky dome.

```javascript
function createMilkyWay(scene, radius = 450) {
  const geo = new THREE.SphereGeometry(radius, 64, 32);
  const material = new THREE.ShaderMaterial({
    uniforms: {
      time:       { value: 0 },
      brightness: { value: 0.25 },
      bandWidth:  { value: 0.18 },      // Angular width of the band
      bandTilt:   { value: 0.4 },       // Tilt angle in radians
      coreGlow:   { value: 0.6 },       // Sagittarius core brightness
      dustLanes:  { value: 0.4 },       // Dark lane intensity
      warmTint:   { value: new THREE.Color(0xffe8cc) },
      coolTint:   { value: new THREE.Color(0xccddff) },
    },
    vertexShader: `
      varying vec3 vWorldDir;
      void main() {
        vWorldDir = normalize((modelMatrix * vec4(position, 1.0)).xyz);
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: MILKY_WAY_FRAG, // See references/celestial-shaders.md
    side: THREE.BackSide,
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  });

  const mesh = new THREE.Mesh(geo, material);
  scene.add(mesh);
  return { mesh, material };
}
```

## Layer 4: Nebulae

### Volumetric Nebula (WebGPU — Raymarched)

Full 3D nebula rendered by marching through an emission/absorption density field.

```javascript
function createVolumetricNebula(scene, options = {}) {
  const {
    position = new THREE.Vector3(100, 80, -200),
    scale = 80,
    type = 'emission',  // emission | reflection | dark | planetary
    color1 = new THREE.Color(0xff2266),
    color2 = new THREE.Color(0x4466ff),
    color3 = new THREE.Color(0x22ffaa),
  } = options;

  const geo = new THREE.BoxGeometry(1, 1, 1);
  const material = new THREE.ShaderMaterial({
    uniforms: {
      cameraPos:    { value: new THREE.Vector3() },
      nebulaScale:  { value: scale },
      color1:       { value: color1 },
      color2:       { value: color2 },
      color3:       { value: color3 },
      density:      { value: 0.5 },
      brightness:   { value: 1.2 },
      noiseOctaves: { value: 5 },
      time:         { value: 0 },
      nebulaType:   { value: NEBULA_TYPE_MAP[type] },
    },
    vertexShader: NEBULA_VERT,
    fragmentShader: NEBULA_FRAG, // See references/celestial-shaders.md
    transparent: true,
    depthWrite: false,
    side: THREE.BackSide,
    blending: THREE.AdditiveBlending,
  });

  const mesh = new THREE.Mesh(geo, material);
  mesh.position.copy(position);
  mesh.scale.setScalar(scale);
  scene.add(mesh);
  return { mesh, material };
}

const NEBULA_TYPE_MAP = { emission: 0, reflection: 1, dark: 2, planetary: 3 };
```

### Billboard Nebula (WebGL Fallback)

Canvas-generated nebula sprite for cheaper rendering.

```javascript
function createBillboardNebula(scene, options = {}) {
  const size = options.size ?? 512;
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = size;
  const ctx = canvas.getContext('2d');

  // Layer multiple radial gradients with noise displacement
  const colors = options.colors ?? ['#ff2266', '#4466ff', '#22ffaa'];
  const centers = [
    { x: size * 0.45, y: size * 0.5 },
    { x: size * 0.55, y: size * 0.45 },
    { x: size * 0.5, y: size * 0.55 },
  ];

  ctx.globalCompositeOperation = 'screen';
  for (let i = 0; i < colors.length; i++) {
    const grad = ctx.createRadialGradient(
      centers[i].x, centers[i].y, 0,
      centers[i].x, centers[i].y, size * 0.4
    );
    grad.addColorStop(0, colors[i] + 'aa');
    grad.addColorStop(0.3, colors[i] + '44');
    grad.addColorStop(0.7, colors[i] + '11');
    grad.addColorStop(1, colors[i] + '00');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, size, size);
  }

  // Add noise texture for structure
  const imgData = ctx.getImageData(0, 0, size, size);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const idx = (y * size + x) * 4;
      const n = fbm2D(x / size * 8, y / size * 8, 5) * 0.5;
      for (let c = 0; c < 3; c++) {
        imgData.data[idx + c] = Math.min(255, imgData.data[idx + c] * (0.7 + n * 0.6));
      }
      imgData.data[idx + 3] = Math.min(255, imgData.data[idx + 3] * (0.5 + n * 0.5));
    }
  }
  ctx.putImageData(imgData, 0, 0);

  const tex = new THREE.CanvasTexture(canvas);
  const spriteMat = new THREE.SpriteMaterial({
    map: tex, transparent: true, blending: THREE.AdditiveBlending,
    depthWrite: false, opacity: options.opacity ?? 0.7,
  });
  const sprite = new THREE.Sprite(spriteMat);
  sprite.scale.setScalar(options.worldSize ?? 100);
  sprite.position.copy(options.position ?? new THREE.Vector3(100, 80, -200));
  scene.add(sprite);
  return sprite;
}

function fbm2D(x, y, octaves) {
  let sum = 0, amp = 1, freq = 1, max = 0;
  for (let i = 0; i < octaves; i++) {
    sum += (Math.sin(x * freq * 127.1 + y * freq * 311.7) * 0.5 + 0.5) * amp;
    max += amp; amp *= 0.5; freq *= 2;
  }
  return sum / max;
}
```

## Layer 5: Celestial Bodies

### Moon

Sphere with phase-accurate lighting based on sun-moon angle.

```javascript
class Moon {
  constructor(scene, options = {}) {
    this.scene = scene;
    this.radius = options.radius ?? 8;
    this.distance = options.distance ?? 350;
    this.phase = options.phase ?? 0.0; // 0=new, 0.5=full, 1=new

    const geo = new THREE.SphereGeometry(this.radius, 32, 32);
    this.material = new THREE.ShaderMaterial({
      uniforms: {
        sunDir:       { value: new THREE.Vector3() },
        moonColor:    { value: new THREE.Color(0xf5f0e0) },
        shadowColor:  { value: new THREE.Color(0x111115) },
        craterScale:  { value: 3.0 },
        craterDepth:  { value: 0.15 },
        glowColor:    { value: new THREE.Color(0xddeeff) },
        glowStrength: { value: 0.3 },
      },
      vertexShader: MOON_VERT,
      fragmentShader: MOON_FRAG, // See references/celestial-shaders.md
      transparent: true,
    });

    this.mesh = new THREE.Mesh(geo, this.material);
    // Glow sprite behind moon
    this.glow = this._createGlow();
    this.group = new THREE.Group();
    this.group.add(this.glow);
    this.group.add(this.mesh);
    this.scene.add(this.group);
  }

  _createGlow() {
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = 128;
    const ctx = canvas.getContext('2d');
    const grad = ctx.createRadialGradient(64, 64, 0, 64, 64, 64);
    grad.addColorStop(0, 'rgba(220,230,255,0.3)');
    grad.addColorStop(0.3, 'rgba(200,215,255,0.1)');
    grad.addColorStop(1, 'rgba(200,215,255,0)');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, 128, 128);
    const tex = new THREE.CanvasTexture(canvas);
    const mat = new THREE.SpriteMaterial({
      map: tex, transparent: true, depthWrite: false,
      blending: THREE.AdditiveBlending,
    });
    const sprite = new THREE.Sprite(mat);
    sprite.scale.setScalar(this.radius * 5);
    return sprite;
  }

  setPhaseAndPosition(phase, elevation, azimuth) {
    this.phase = phase;
    // Position on sky dome
    const elRad = elevation * Math.PI / 180;
    const azRad = azimuth * Math.PI / 180;
    this.group.position.set(
      Math.cos(elRad) * Math.sin(azRad) * this.distance,
      Math.sin(elRad) * this.distance,
      Math.cos(elRad) * Math.cos(azRad) * this.distance
    );
    // Sun direction relative to moon for phase lighting
    const phaseAngle = phase * Math.PI * 2;
    this.material.uniforms.sunDir.value.set(
      Math.sin(phaseAngle), 0.1, -Math.cos(phaseAngle)
    ).normalize();
  }

  dispose() { this.scene.remove(this.group); }
}
```

## Layer 6: Transient Events

### Shooting Stars / Meteors

Bright streak that flares and fades over 0.5–2 seconds.

```javascript
class MeteorSystem {
  constructor(scene, options = {}) {
    this.scene = scene;
    this.rate = options.rate ?? 0.15;     // Meteors per second
    this.skyRadius = options.skyRadius ?? 380;
    this.meteors = [];
    this._timer = 0;
  }

  _spawn() {
    // Random start point on upper hemisphere
    const theta = Math.random() * Math.PI * 2;
    const phi = Math.random() * Math.PI * 0.4; // Upper sky
    const start = new THREE.Vector3(
      Math.sin(phi) * Math.cos(theta) * this.skyRadius,
      Math.cos(phi) * this.skyRadius,
      Math.sin(phi) * Math.sin(theta) * this.skyRadius
    );

    // Direction: roughly downward with lateral drift
    const dir = new THREE.Vector3(
      (Math.random() - 0.5) * 0.5,
      -0.7 - Math.random() * 0.3,
      (Math.random() - 0.5) * 0.5
    ).normalize();

    const length = 15 + Math.random() * 30;
    const end = start.clone().add(dir.clone().multiplyScalar(length));

    // Build trail geometry
    const positions = new Float32Array(6); // 2 points
    positions[0] = start.x; positions[1] = start.y; positions[2] = start.z;
    positions[3] = end.x;   positions[4] = end.y;   positions[5] = end.z;

    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));

    const mat = new THREE.LineBasicMaterial({
      color: 0xffffff, transparent: true, opacity: 1.0,
      blending: THREE.AdditiveBlending, depthWrite: false,
    });

    const line = new THREE.Line(geo, mat);
    this.scene.add(line);

    // Glow head
    const headMat = new THREE.SpriteMaterial({
      color: 0xffffcc, transparent: true, opacity: 0.8,
      blending: THREE.AdditiveBlending, depthWrite: false,
    });
    const head = new THREE.Sprite(headMat);
    head.scale.setScalar(2);
    head.position.copy(end);
    this.scene.add(head);

    const duration = 0.4 + Math.random() * 1.2;
    this.meteors.push({ line, head, mat, headMat, life: duration, maxLife: duration });
  }

  update(dt) {
    this._timer += dt;
    if (this._timer > 1 / this.rate) {
      this._timer = 0;
      if (Math.random() < 0.7) this._spawn(); // Some variance
    }

    for (let i = this.meteors.length - 1; i >= 0; i--) {
      const m = this.meteors[i];
      m.life -= dt;
      const t = m.life / m.maxLife;
      // Flare then fade: peak brightness at t≈0.7
      const brightness = t > 0.7 ? (1 - t) / 0.3 : t / 0.7;
      m.mat.opacity = brightness;
      m.headMat.opacity = brightness * 0.8;

      if (m.life <= 0) {
        this.scene.remove(m.line);
        this.scene.remove(m.head);
        m.line.geometry.dispose();
        this.meteors.splice(i, 1);
      }
    }
  }

  dispose() {
    for (const m of this.meteors) {
      this.scene.remove(m.line);
      this.scene.remove(m.head);
    }
  }
}
```

### Comet

Bright nucleus with two tails — blue-white ion tail (straight, away from sun) and
diffuse dust tail (curved, trailing orbit).

```javascript
function createComet(scene, options = {}) {
  const pos = options.position ?? new THREE.Vector3(-150, 100, -250);
  const sunDir = options.sunDir ?? new THREE.Vector3(0.3, -0.5, 0.8).normalize();

  const group = new THREE.Group();
  group.position.copy(pos);

  // Nucleus
  const nucleus = new THREE.Mesh(
    new THREE.SphereGeometry(1.5, 16, 16),
    new THREE.MeshBasicMaterial({ color: 0xeeeeff })
  );
  group.add(nucleus);

  // Coma glow
  const comaMat = new THREE.SpriteMaterial({
    color: 0xccddff, transparent: true, opacity: 0.5,
    blending: THREE.AdditiveBlending, depthWrite: false,
  });
  const coma = new THREE.Sprite(comaMat);
  coma.scale.setScalar(12);
  group.add(coma);

  // Ion tail (straight, anti-sun)
  const ionDir = sunDir.clone().negate();
  const ionPoints = [];
  for (let i = 0; i < 50; i++) {
    const t = i / 49;
    ionPoints.push(ionDir.clone().multiplyScalar(t * 120));
  }
  const ionGeo = new THREE.BufferGeometry().setFromPoints(ionPoints);
  const ionMat = new THREE.LineBasicMaterial({
    color: 0x4488ff, transparent: true, opacity: 0.4,
    blending: THREE.AdditiveBlending, depthWrite: false,
  });
  group.add(new THREE.Line(ionGeo, ionMat));

  // Dust tail (curved, broader)
  const dustDir = ionDir.clone().add(new THREE.Vector3(0.3, 0.1, 0)).normalize();
  const dustPoints = [];
  for (let i = 0; i < 40; i++) {
    const t = i / 39;
    const curve = dustDir.clone().multiplyScalar(t * 80);
    curve.x += Math.sin(t * 2) * 10 * t;
    curve.y += t * 5;
    dustPoints.push(curve);
  }
  const dustGeo = new THREE.BufferGeometry().setFromPoints(dustPoints);
  const dustMat = new THREE.LineBasicMaterial({
    color: 0xffddaa, transparent: true, opacity: 0.25,
    blending: THREE.AdditiveBlending, depthWrite: false,
  });
  group.add(new THREE.Line(dustGeo, dustMat));

  scene.add(group);
  return group;
}
```

## Sky Controller

Master orchestrator that coordinates all layers based on time and configuration.

```javascript
class NightSkyController {
  constructor(scene, camera, options = {}) {
    this.scene = scene;
    this.camera = camera;

    this.skyDome = createSkyDome();
    this.scene.add(this.skyDome);

    this.starfield = new Starfield(scene, {
      count: options.starCount ?? 8000,
      twinkleSpeed: options.twinkleSpeed ?? 1.0,
    });

    this.milkyWay = createMilkyWay(scene);
    this.moon = new Moon(scene);
    this.meteors = new MeteorSystem(scene, { rate: options.meteorRate ?? 0.1 });
    this.nebulae = [];

    // Time: 0=sunset, 0.5=midnight, 1=sunrise
    this.nightProgress = options.startTime ?? 0.5;
  }

  addNebula(options) {
    const nebula = createBillboardNebula(this.scene, options);
    this.nebulae.push(nebula);
    return nebula;
  }

  update(dt) {
    const t = performance.now() * 0.001;
    this.starfield.update(t);
    this.meteors.update(dt);

    // Moon position from night progress
    const moonElev = Math.sin(this.nightProgress * Math.PI) * 60;
    const moonAz = this.nightProgress * 180 - 90;
    this.moon.setPhaseAndPosition(this.moon.phase, moonElev, moonAz);

    // Milky Way rotation
    this.milkyWay.mesh.rotation.y = t * 0.001;
  }

  setNightProgress(t) { this.nightProgress = Math.max(0, Math.min(1, t)); }
  setMoonPhase(phase) { this.moon.phase = phase; }

  dispose() {
    this.starfield.dispose();
    this.moon.dispose();
    this.meteors.dispose();
    this.scene.remove(this.skyDome);
    this.scene.remove(this.milkyWay.mesh);
    for (const n of this.nebulae) this.scene.remove(n);
  }
}
```

## Night Sky Presets

```javascript
const SKY_PRESETS = {
  pristineMountain: {
    starCount: 12000, lightPollution: 0.0, milkyWayBrightness: 0.35,
    meteorRate: 0.12, moonPhase: 0.0,
    description: 'Remote mountain — maximum stars, vivid Milky Way, no moon',
  },
  fullMoonNight: {
    starCount: 4000, lightPollution: 0.05, milkyWayBrightness: 0.08,
    meteorRate: 0.05, moonPhase: 0.5,
    description: 'Bright full moon washes out fainter stars and Milky Way',
  },
  suburbanSky: {
    starCount: 2000, lightPollution: 0.4, milkyWayBrightness: 0.02,
    meteorRate: 0.08, moonPhase: 0.25,
    description: 'Light pollution hides faint stars, warm horizon glow',
  },
  meteorShower: {
    starCount: 10000, lightPollution: 0.0, milkyWayBrightness: 0.3,
    meteorRate: 0.8, moonPhase: 0.0,
    description: 'Peak Perseids — constant streaks across a pristine sky',
  },
  deepSpace: {
    starCount: 20000, lightPollution: 0.0, milkyWayBrightness: 0.5,
    meteorRate: 0.02, moonPhase: 0.0, nebulae: true, galaxies: true,
    description: 'Fantasy deep-space vista — dense stars, vivid nebulae, galaxies',
  },
  twilight: {
    starCount: 1000, lightPollution: 0.1, milkyWayBrightness: 0.0,
    meteorRate: 0.02, moonPhase: 0.4,
    description: 'Early evening — only brightest stars and planets visible',
  },
};
```

## Performance Guidelines

| Layer | Cost | Draw Calls | Notes |
|-------|------|-----------|-------|
| Sky Dome | Negligible | 1 | BackSide sphere, simple gradient |
| Starfield | Low | 1 (Points) | 8K–20K points, all in vertex shader |
| Milky Way | Low | 1 | FBM in fragment on BackSide sphere |
| Nebula (billboard) | Low | 1 per nebula | Sprite, pre-baked canvas texture |
| Nebula (volumetric) | High | 1 | Raymarched — limit steps to 48 |
| Moon | Low | 2 | Sphere + glow sprite |
| Meteors | Negligible | 0–3 | Ephemeral, 1–2 lines active at a time |
| Comet | Low | 3 | Nucleus + 2 tail lines |

**Total**: Full night sky runs at **5–8 draw calls** with additive blending everywhere.

**Key optimizations**:
- All star animation (twinkle) in vertex shader — zero JS per-star loops.
- `AdditiveBlending` on all layers — no sort order needed for transparent objects.
- `depthWrite: false` on everything except the sky dome — celestial objects never occlude each other via depth.
- Stars use `gl_PointSize` with magnitude-based scaling — one geometry, one draw call.
- Nebula billboard is pre-baked to canvas — fragment shader is a single texture sample.

## Common Pitfalls

1. **Stars visible through Moon / planets**: Sky layers need explicit render order. Set `renderOrder` so dome < stars < milky way < nebulae < moon.
2. **Stars look like a flat grid**: Ensure uniform sphere distribution using `acos(2r-1)` for phi, not linear sampling. Linear creates polar clustering.
3. **All stars same color**: Must use blackbody temperature → RGB conversion. Even subtle color variation (warm yellow, cool blue) is critical for realism.
4. **Milky Way too bright / uniform**: Use dust lane subtraction and core brightening near Sagittarius. The Milky Way is not a smooth band — it has structure.
5. **No sense of depth**: Layer multiple elements at slightly different radii and let parallax from camera rotation create subtle depth. Nebulae at 450, stars at 400, dome at 500.

## References

- `references/celestial-shaders.md` — Complete GLSL vertex/fragment shaders for sky dome, stars, Milky Way, nebula raymarching, moon surface, and WGSL star compute.
- `references/celestial-catalog.md` — Nebula type profiles, deep-sky objects, constellation data format, and artistic direction for different sky moods.

---

<!-- file: celestial-shaders.md -->

# Celestial Shaders Reference

Complete shader implementations for night sky rendering: sky dome gradient, starfield
with twinkle and spectral color, Milky Way band, volumetric nebula raymarching, moon
surface with procedural craters, and WGSL compute star generation.

## Sky Dome Fragment Shader

Multi-stop gradient with horizon glow and moon ambient illumination.

```glsl
// sky_dome.frag
precision highp float;

uniform vec3  zenithColor;
uniform vec3  midColor;
uniform vec3  horizonColor;
uniform vec3  horizonGlow;
uniform float glowStrength;
uniform float lightPollution;
uniform vec3  moonPos;
uniform float moonGlowStr;

varying vec3 vWorldDir;

void main() {
  vec3 dir = normalize(vWorldDir);
  float elevation = dir.y; // -1 (nadir) to +1 (zenith)

  // Multi-stop gradient
  vec3 sky;
  if (elevation > 0.3) {
    sky = mix(midColor, zenithColor, (elevation - 0.3) / 0.7);
  } else if (elevation > 0.0) {
    sky = mix(horizonColor, midColor, elevation / 0.3);
  } else {
    sky = mix(horizonGlow, horizonColor, (elevation + 1.0));
  }

  // Horizon glow band
  float horizonBand = exp(-abs(elevation) * 8.0) * glowStrength;
  sky += horizonGlow * horizonBand;

  // Light pollution: warm orange-ish brightening at horizon
  float pollution = exp(-abs(elevation) * 4.0) * lightPollution;
  sky += vec3(0.15, 0.1, 0.05) * pollution;

  // Moon ambient glow
  float moonAngle = max(dot(dir, normalize(moonPos)), 0.0);
  float moonHalo = pow(moonAngle, 16.0) * moonGlowStr;
  float moonWideGlow = pow(moonAngle, 3.0) * moonGlowStr * 0.15;
  sky += vec3(0.6, 0.65, 0.8) * (moonHalo + moonWideGlow);

  // Zodiacal light (faint cone along ecliptic near horizon)
  float zodiacal = exp(-abs(elevation) * 6.0) * 0.02 * (1.0 - lightPollution);
  sky += vec3(0.12, 0.1, 0.08) * zodiacal;

  gl_FragColor = vec4(sky, 1.0);
}
```

## Star Vertex Shader

Magnitude-based sizing, spectral coloring, and multi-frequency twinkle.

```glsl
// star.vert
attribute vec4 aStarData; // rgb color, magnitude

uniform float time;
uniform float twinkleSpeed;
uniform float brightnessExp;
uniform float baseSizePx;
uniform float exposure;

varying vec3  vColor;
varying float vBrightness;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void main() {
  vec3 starColor = aStarData.rgb;
  float magnitude = aStarData.w;

  // Magnitude → brightness: each magnitude is ~2.512× dimmer
  // Normalized so mag 0 = 1.0 brightness
  float brightness = pow(2.512, -magnitude) * exposure;

  // Point size from brightness
  float size = baseSizePx * pow(brightness, 0.5);
  size = clamp(size, 0.5, 8.0);

  // Twinkle: multi-frequency scintillation
  float twinklePhase = hash(position.xy) * 6.283;
  float twinkle1 = sin(time * twinkleSpeed * 2.3 + twinklePhase) * 0.15;
  float twinkle2 = sin(time * twinkleSpeed * 5.7 + twinklePhase * 2.0) * 0.08;
  float twinkle3 = sin(time * twinkleSpeed * 11.0 + twinklePhase * 3.0) * 0.04;
  float twinkle = 1.0 + twinkle1 + twinkle2 + twinkle3;

  // Brighter stars twinkle less (they're larger apparent discs)
  float twinkleAmt = mix(1.0, twinkle, clamp(1.0 - brightness * 0.5, 0.2, 1.0));

  vColor = starColor;
  vBrightness = brightness * twinkleAmt;

  vec4 mvPos = modelViewMatrix * vec4(position, 1.0);
  gl_Position = projectionMatrix * mvPos;
  gl_PointSize = size * twinkleAmt;
}
```

## Star Fragment Shader

Soft glow falloff for natural star appearance.

```glsl
// star.frag
precision highp float;

uniform float glowFalloff;

varying vec3  vColor;
varying float vBrightness;

void main() {
  vec2 center = gl_PointCoord - 0.5;
  float dist = length(center);

  // Core + glow profile
  float core = smoothstep(0.5, 0.05, dist);
  float glow = exp(-dist * dist / (glowFalloff * glowFalloff)) * 0.6;
  float alpha = core + glow;

  // Bright stars get a slight diffraction spike hint
  float spike = 0.0;
  if (vBrightness > 0.5) {
    float angle = atan(center.y, center.x);
    spike = pow(abs(cos(angle * 2.0)), 32.0) * (1.0 - dist * 3.0);
    spike = max(spike, 0.0) * (vBrightness - 0.5) * 0.3;
  }

  vec3 col = vColor * vBrightness;
  gl_FragColor = vec4(col, (alpha + spike) * vBrightness);
}
```

## Milky Way Fragment Shader

Procedural galactic band with FBM structure, dust lanes, and core brightening.

```glsl
// milky_way.frag
precision highp float;

uniform float brightness;
uniform float bandWidth;
uniform float bandTilt;
uniform float coreGlow;
uniform float dustLanes;
uniform vec3  warmTint;
uniform vec3  coolTint;
uniform float time;

varying vec3 vWorldDir;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
  vec2 i = floor(p); vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1,0)), f.x),
             mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), f.x), f.y);
}

float fbm(vec2 p, int oct) {
  float sum = 0.0, amp = 1.0, maxA = 0.0;
  for (int i = 0; i < 6; i++) {
    if (i >= oct) break;
    sum += noise(p) * amp; maxA += amp;
    amp *= 0.5; p *= 2.1;
  }
  return sum / maxA;
}

void main() {
  vec3 dir = normalize(vWorldDir);

  // Transform to galactic coordinates (tilted band)
  float galLat = dir.y * cos(bandTilt) - dir.z * sin(bandTilt);
  float galLon = atan(dir.x, dir.z * cos(bandTilt) + dir.y * sin(bandTilt));

  // Band envelope
  float band = exp(-galLat * galLat / (bandWidth * bandWidth));

  // FBM structure (star clouds)
  vec2 uv = vec2(galLon * 2.0, galLat * 8.0);
  float structure = fbm(uv * 3.0, 5);
  structure = structure * 0.7 + 0.3;

  // Dust lanes (dark absorbing regions)
  float dust = fbm(uv * 4.0 + 1.7, 4);
  dust = smoothstep(0.35, 0.55, dust) * dustLanes;

  // Core brightening (Sagittarius direction ≈ galLon ≈ 0)
  float core = exp(-galLon * galLon * 2.0) * coreGlow;

  // Combine
  float mw = band * structure * (1.0 - dust) + core * band;
  mw *= brightness;

  // Color: warmer near core, cooler at edges
  vec3 col = mix(coolTint, warmTint, core * 2.0 + 0.3);
  col *= mw;

  // Scattered star-like noise (tiny bright points in the band)
  float starNoise = noise(uv * 80.0);
  starNoise = pow(starNoise, 8.0) * band * 0.3;
  col += vec3(1.0) * starNoise;

  gl_FragColor = vec4(col, mw);
}
```

## Volumetric Nebula Fragment Shader

Raymarched emission nebula with multi-color layering and absorption.

```glsl
// nebula.frag
precision highp float;

uniform vec3  cameraPos;
uniform float nebulaScale;
uniform vec3  color1;
uniform vec3  color2;
uniform vec3  color3;
uniform float density;
uniform float brightness;
uniform float time;
uniform int   nebulaType; // 0=emission, 1=reflection, 2=dark, 3=planetary

varying vec3 vWorldPos;

#define MAX_STEPS 48
#define STEP_SIZE 0.04

vec3 hash3(vec3 p) {
  p = vec3(dot(p, vec3(127.1,311.7,74.7)),
           dot(p, vec3(269.5,183.3,246.1)),
           dot(p, vec3(113.5,271.9,124.6)));
  return fract(sin(p) * 43758.5453);
}

float noise3D(vec3 p) {
  vec3 i = floor(p); vec3 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = dot(hash3(i), f);
  float b = dot(hash3(i + vec3(1,0,0)), f - vec3(1,0,0));
  float c = dot(hash3(i + vec3(0,1,0)), f - vec3(0,1,0));
  float d = dot(hash3(i + vec3(1,1,0)), f - vec3(1,1,0));
  float e = dot(hash3(i + vec3(0,0,1)), f - vec3(0,0,1));
  float f1 = dot(hash3(i + vec3(1,0,1)), f - vec3(1,0,1));
  float g = dot(hash3(i + vec3(0,1,1)), f - vec3(0,1,1));
  float h = dot(hash3(i + vec3(1,1,1)), f - vec3(1,1,1));
  return mix(mix(mix(a,b,f.x), mix(c,d,f.x), f.y),
             mix(mix(e,f1,f.x), mix(g,h,f.x), f.y), f.z);
}

float fbm(vec3 p, int oct) {
  float s = 0.0, a = 1.0, m = 0.0;
  for (int i = 0; i < 6; i++) {
    if (i >= oct) break;
    s += noise3D(p) * a; m += a;
    a *= 0.5; p *= 2.0;
  }
  return s / m;
}

// Ray-box intersection
vec2 boxIntersect(vec3 ro, vec3 rd) {
  vec3 inv = 1.0 / rd;
  vec3 t1 = (-0.5 - ro) * inv;
  vec3 t2 = (0.5 - ro) * inv;
  vec3 tmin = min(t1, t2);
  vec3 tmax = max(t1, t2);
  float near = max(max(tmin.x, tmin.y), tmin.z);
  float far = min(min(tmax.x, tmax.y), tmax.z);
  return vec2(max(near, 0.0), far);
}

void main() {
  vec3 ro = (inverse(modelMatrix) * vec4(cameraPos, 1.0)).xyz;
  vec3 rd = normalize(vWorldPos - cameraPos);
  rd = normalize((inverse(modelMatrix) * vec4(rd, 0.0)).xyz);

  vec2 t = boxIntersect(ro, rd);
  if (t.x > t.y) discard;

  vec4 result = vec4(0.0);
  float step = (t.y - t.x) / float(MAX_STEPS);
  float tt = t.x;

  for (int i = 0; i < MAX_STEPS; i++) {
    if (result.a > 0.95) break;
    vec3 p = ro + rd * tt;

    // Multi-scale density
    float d = fbm(p * 3.0 + time * 0.01, 5);
    d = smoothstep(0.3, 0.7, d) * density;

    if (d > 0.001) {
      // Color layers based on position within volume
      float r = length(p);
      vec3 col;
      if (nebulaType == 3) {
        // Planetary: shell structure
        float shell = abs(r - 0.3);
        d *= exp(-shell * shell * 20.0);
        col = mix(color1, color2, smoothstep(0.2, 0.4, r));
      } else {
        // Emission/reflection: layered color by noise
        float colorNoise = fbm(p * 2.0, 3);
        col = mix(color1, color2, smoothstep(0.3, 0.6, colorNoise));
        col = mix(col, color3, smoothstep(0.55, 0.8, colorNoise));
      }

      // Bright filament highlights
      float filament = pow(fbm(p * 8.0, 4), 3.0);
      col += vec3(1.0) * filament * 0.4;

      // Central glow
      float centralGlow = exp(-r * r * 6.0) * 0.5;
      col += color1 * centralGlow;

      col *= brightness;

      float alpha = 1.0 - exp(-d * step * 20.0);
      result.rgb += col * alpha * (1.0 - result.a);
      result.a += alpha * (1.0 - result.a);
    }

    tt += step;
  }

  if (nebulaType == 2) {
    // Dark nebula: absorb background light
    result.rgb = vec3(0.0);
    result.a = result.a * 0.8;
    gl_FragColor = vec4(result.rgb, result.a);
  } else {
    gl_FragColor = result;
  }
}
```

## Nebula Vertex Shader

Pass world position for raymarching origin calculation.

```glsl
// nebula.vert
varying vec3 vWorldPos;
void main() {
  vWorldPos = (modelMatrix * vec4(position, 1.0)).xyz;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
```

## Moon Fragment Shader

Procedural cratered surface with phase-accurate lighting.

```glsl
// moon.frag
precision highp float;

uniform vec3  sunDir;
uniform vec3  moonColor;
uniform vec3  shadowColor;
uniform float craterScale;
uniform float craterDepth;

varying vec3 vNormal;
varying vec3 vPosition;

float hash(vec3 p) {
  return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

// Simplified crater function using Voronoi
float craters(vec3 p) {
  vec3 i = floor(p); vec3 f = fract(p);
  float minDist = 1.0;
  for (int x = -1; x <= 1; x++)
  for (int y = -1; y <= 1; y++)
  for (int z = -1; z <= 1; z++) {
    vec3 nb = vec3(float(x), float(y), float(z));
    vec3 pt = vec3(hash(i+nb), hash((i+nb)*1.3), hash((i+nb)*1.7));
    float d = length(nb + pt - f);
    minDist = min(minDist, d);
  }
  return smoothstep(0.0, 0.4, minDist); // Crater rim profile
}

void main() {
  vec3 N = normalize(vNormal);
  vec3 L = normalize(sunDir);

  // Crater surface detail
  float c1 = craters(vPosition * craterScale);
  float c2 = craters(vPosition * craterScale * 3.0) * 0.4;
  float surface = c1 + c2;

  // Perturb normal by crater depth
  vec3 perturbedN = normalize(N + dFdx(surface) * craterDepth * 10.0
                                 + dFdy(surface) * craterDepth * 10.0);

  // Phase lighting
  float NdotL = dot(perturbedN, L);
  float diffuse = max(NdotL, 0.0);

  // Lunar surface: mix lit moonColor with dark shadowColor
  vec3 color = mix(shadowColor, moonColor * surface, diffuse);

  // Subtle limb darkening
  float limbDark = pow(max(dot(N, normalize(-vPosition)), 0.0), 0.3);
  color *= 0.7 + 0.3 * limbDark;

  // Earthshine: very faint illumination on dark side
  float earthshine = max(-NdotL, 0.0) * 0.03;
  color += vec3(0.3, 0.35, 0.5) * earthshine;

  gl_FragColor = vec4(color, 1.0);
}
```

## Moon Vertex Shader

```glsl
// moon.vert
varying vec3 vNormal;
varying vec3 vPosition;
void main() {
  vNormal = normalize(normalMatrix * normal);
  vPosition = position;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
```

## WGSL Compute: Star Catalog Generation

Generate a large starfield on the GPU with proper spectral distribution.

```wgsl
// star_generate.wgsl
struct Star {
  position: vec4<f32>,  // xyz on unit sphere, w = magnitude
  color: vec4<f32>,     // rgb spectral color, w = twinkle seed
}

@group(0) @binding(0) var<storage, read_write> stars: array<Star>;
@group(0) @binding(1) var<uniform> params: StarGenParams;

struct StarGenParams {
  count: u32,
  radius: f32,
  minMag: f32,
  maxMag: f32,
  seed: f32,
}

fn hash(n: f32) -> f32 { return fract(sin(n) * 43758.5453); }
fn hash2(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453); }

fn blackbody(tempK: f32) -> vec3<f32> {
  let t = tempK / 100.0;
  var r: f32; var g: f32; var b: f32;
  if (t <= 66.0) {
    r = 1.0;
    g = (99.47 * log(t) - 161.12) / 255.0;
    if (t <= 19.0) { b = 0.0; }
    else { b = (138.52 * log(t - 10.0) - 305.04) / 255.0; }
  } else {
    r = 329.7 * pow(t - 60.0, -0.1332) / 255.0;
    g = 288.12 * pow(t - 60.0, -0.0755) / 255.0;
    b = 1.0;
  }
  return clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(256)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  if (gid.x >= params.count) { return; }

  let i = f32(gid.x);
  let s = params.seed + i;

  // Uniform sphere distribution
  let theta = hash(s * 1.1) * 6.283185;
  let phi = acos(2.0 * hash(s * 2.2) - 1.0);
  let pos = vec3<f32>(
    sin(phi) * cos(theta),
    sin(phi) * sin(theta),
    cos(phi)
  ) * params.radius;

  // Magnitude (exponential: many faint, few bright)
  let mag = params.minMag + pow(hash(s * 3.3), 0.4) * (params.maxMag - params.minMag);

  // Temperature from spectral distribution
  let r = hash(s * 4.4);
  var temp: f32;
  if (r < 0.003) { temp = 30000.0 + r * 5000000.0; }
  else if (r < 0.01) { temp = 10000.0 + r * 1000000.0; }
  else if (r < 0.04) { temp = 7500.0 + r * 60000.0; }
  else if (r < 0.11) { temp = 6000.0 + r * 15000.0; }
  else if (r < 0.23) { temp = 5200.0 + r * 5000.0; }
  else if (r < 0.50) { temp = 3700.0 + r * 3000.0; }
  else { temp = 2400.0 + r * 2600.0; }

  let col = blackbody(temp);
  let twinkleSeed = hash(s * 5.5);

  stars[gid.x].position = vec4<f32>(pos, mag);
  stars[gid.x].color = vec4<f32>(col, twinkleSeed);
}
```

## Performance Notes

- **Additive blending everywhere**: All celestial layers use `THREE.AdditiveBlending` — no transparency sorting needed. This is the single biggest performance win.
- **Star twinkle in vertex shader**: Multi-frequency sine with hash-based phase — each star is unique, zero JS cost.
- **Diffraction spikes**: Only computed for stars with `vBrightness > 0.5` (the brightest ~5%). Cheap branch.
- **Nebula step count**: 48 steps is the sweet spot. Below 32 you get banding, above 64 gives diminishing returns.
- **Billboard nebulae**: Pre-bake to canvas once. For animated nebulae, update canvas at 2–4 FPS, not every frame.
- **Moon craters**: Voronoi computed in fragment shader. For static moons, bake to texture once.

---

<!-- file: celestial-catalog.md -->

# Celestial Catalog Reference

Nebula type profiles, deep-sky object presets, constellation data format, eclipse
configurations, and artistic direction for different sky moods.

## Nebula Types

### Emission Nebula

**Character**: Glowing gas clouds ionized by nearby hot stars. Vivid colors —
hydrogen-alpha red/pink, oxygen-III teal/green, sulfur-II orange.

```javascript
const EMISSION = {
  colors: {
    primary: 0xff2266,     // H-alpha (hydrogen, dominant)
    secondary: 0x22aaff,   // OIII (oxygen)
    tertiary: 0xffaa22,    // SII (sulfur)
  },
  density: 0.6,
  brightness: 1.4,
  noiseOctaves: 5,
  filamentStrength: 0.5,
  centralGlow: 0.4,
  examples: ['Orion Nebula (M42)', 'Eagle Nebula (M16)', 'Lagoon Nebula (M8)'],
  artistic: `
    Rich, vivid, and dramatic. Tendrils of glowing gas wrap around dark
    voids. Central regions are brightest with colors bleeding outward.
    Filaments of brighter emission thread through the volume. Think "cosmic
    watercolor" — colors should blend and layer, never feel flat or uniform.
    The Hubble Palette (SHO) maps SII→red, H-alpha→green, OIII→blue for
    extra-vivid false color if desired.
  `,
};
```

### Reflection Nebula

**Character**: Dust clouds reflecting starlight. Blue-dominant (scatters blue
light more efficiently, like Earth's sky).

```javascript
const REFLECTION = {
  colors: {
    primary: 0x4488dd,     // Scattered blue
    secondary: 0x6699cc,   // Cooler blue
    tertiary: 0xaabbdd,    // Pale blue-white
  },
  density: 0.4,
  brightness: 0.8,
  noiseOctaves: 4,
  filamentStrength: 0.2,
  centralGlow: 0.6,        // Central star illumination
  examples: ['Witch Head (IC 2118)', 'Pleiades nebulosity'],
  artistic: `
    Ethereal and delicate. Soft blue glow around a central bright point.
    Less structured than emission — more like a soft diffuse haze. Edges
    fade gently into space. Beautiful when combined with a prominent
    central star. The color is almost always blue due to Rayleigh-like
    scattering physics.
  `,
};
```

### Dark Nebula

**Character**: Dense dust clouds that absorb background starlight. Visible only
as silhouettes against brighter fields.

```javascript
const DARK = {
  colors: {
    primary: 0x000000,     // Pure absorption
    secondary: 0x110808,   // Very faint reddened edges
    tertiary: 0x080808,
  },
  density: 0.8,
  brightness: 0.0,         // Absorbs, doesn't emit
  noiseOctaves: 5,
  filamentStrength: 0.6,   // Dark tendrils reaching out
  examples: ['Horsehead Nebula', 'Barnard 68', 'Coal Sack'],
  artistic: `
    The absence of light as art. Dark nebulae carve dramatic shapes out
    of the star field behind them. Edges can be razor-sharp or soft and
    pillowy. They work best when placed against a rich star background or
    bright emission region. The Horsehead is the classic example — a dark
    silhouette against a red emission backdrop.
  `,
  rendering: `
    Render as opacity mask: high density → high alpha but zero color.
    In the shader, set result.rgb = vec3(0) and use result.a to darken
    background. Requires non-additive blending (NormalBlending).
  `,
};
```

### Planetary Nebula

**Character**: Dying star's expelled shell. Small, bright, often ring or
hourglass shaped. Intense colors.

```javascript
const PLANETARY = {
  colors: {
    primary: 0x00ffaa,     // OIII (very common)
    secondary: 0xff4488,   // H-alpha
    tertiary: 0x4444ff,    // HeII
  },
  density: 0.7,
  brightness: 1.6,
  noiseOctaves: 4,
  shellRadius: 0.3,        // Normalized shell distance from center
  shellWidth: 0.08,
  centralStar: true,
  examples: ['Ring Nebula (M57)', 'Helix Nebula (NGC 7293)', 'Cat\'s Eye (NGC 6543)'],
  artistic: `
    Jewel-like and geometric. Unlike diffuse nebulae, planetaries have
    clear structure — rings, shells, bipolar lobes. A bright central
    white dwarf star sits at the center. Colors can be extremely vivid,
    almost neon. Small scale but intense impact. Think "cosmic gemstone."
    The shell structure creates natural bright edges and dark centers.
  `,
};
```

### Supernova Remnant

**Character**: Expanding shockwave from stellar explosion. Filamentary, energetic,
chaotic structure.

```javascript
const SUPERNOVA_REMNANT = {
  colors: {
    primary: 0xff4422,     // Shock-heated hydrogen
    secondary: 0x22aaff,   // Synchrotron (blue)
    tertiary: 0xffee44,    // Hot ejecta
  },
  density: 0.5,
  brightness: 1.0,
  noiseOctaves: 6,         // High detail for filaments
  filamentStrength: 0.8,   // Very filamentary
  expansionShell: true,
  examples: ['Crab Nebula (M1)', 'Veil Nebula (NGC 6960)', 'Cassiopeia A'],
  artistic: `
    Wild and energetic. Unlike the soft glow of emission nebulae, SNRs
    have sharp filamentary structure — think tangled threads of light.
    Colors can include unusual combinations (red + blue synchrotron).
    Often asymmetric and chaotic. The sense of explosive energy should
    come through in the visual texture. Use high noise octaves for
    detailed filamentary structure.
  `,
};
```

## Deep-Sky Object Presets

Pre-configured objects for quick scene building.

```javascript
const DEEP_SKY_OBJECTS = {
  orionNebula: {
    type: 'emission',
    position: new THREE.Vector3(-80, 40, -300),
    scale: 60,
    colors: [0xff3366, 0x4488cc, 0xffaa44],
    brightness: 1.2,
  },
  pillarsOfCreation: {
    type: 'emission',
    position: new THREE.Vector3(120, 60, -280),
    scale: 45,
    colors: [0xff6633, 0x22aa55, 0x3366cc],
    brightness: 1.0,
  },
  horsehead: {
    type: 'dark',  // Dark against emission background
    position: new THREE.Vector3(-50, 70, -320),
    scale: 30,
    colors: [0x000000, 0x110505, 0x050505],
    brightness: 0,
    backgroundEmission: { color: 0xff3344, brightness: 0.6 },
  },
  ringNebula: {
    type: 'planetary',
    position: new THREE.Vector3(200, 100, -250),
    scale: 20,
    colors: [0x00ffaa, 0xff4488, 0x4444ff],
    brightness: 1.5,
  },
  crabNebula: {
    type: 'supernova_remnant',
    position: new THREE.Vector3(-150, 90, -350),
    scale: 25,
    colors: [0xff4422, 0x22aaff, 0xffee44],
    brightness: 1.0,
  },
  pleiadesCluster: {
    type: 'reflection',
    position: new THREE.Vector3(60, 110, -280),
    scale: 50,
    colors: [0x4488dd, 0x6699cc, 0xaabbdd],
    brightness: 0.7,
    embeddedStars: 7,  // Bright blue stars within
  },
};
```

## Constellation Data Format

Store constellations as star positions + line connections for optional overlays.

```javascript
const CONSTELLATION_FORMAT = {
  name: 'Orion',
  stars: [
    { id: 'betelgeuse', ra: 88.79,  dec: 7.41,  mag: 0.5,  temp: 3500 },
    { id: 'rigel',      ra: 78.63,  dec: -8.20, mag: 0.13, temp: 11000 },
    { id: 'bellatrix',  ra: 81.28,  dec: 6.35,  mag: 1.64, temp: 22000 },
    { id: 'mintaka',    ra: 83.00,  dec: -0.30, mag: 2.23, temp: 30000 },
    { id: 'alnilam',    ra: 84.05,  dec: -1.20, mag: 1.69, temp: 27500 },
    { id: 'alnitak',    ra: 85.19,  dec: -1.94, mag: 1.77, temp: 30000 },
    { id: 'saiph',      ra: 86.94,  dec: -9.67, mag: 2.09, temp: 26000 },
  ],
  lines: [
    ['betelgeuse', 'bellatrix'],
    ['betelgeuse', 'mintaka'],
    ['bellatrix', 'mintaka'],
    ['mintaka', 'alnilam'],
    ['alnilam', 'alnitak'],
    ['alnitak', 'saiph'],
    ['mintaka', 'rigel'],
    ['rigel', 'saiph'],
  ],
};

// Convert RA/Dec to 3D position on sky sphere
function raDecToPosition(ra, dec, radius = 400) {
  const raRad = (ra / 360) * Math.PI * 2;
  const decRad = (dec / 180) * Math.PI;
  return new THREE.Vector3(
    Math.cos(decRad) * Math.cos(raRad) * radius,
    Math.sin(decRad) * radius,
    Math.cos(decRad) * Math.sin(raRad) * radius
  );
}

// Render constellation lines
function drawConstellationLines(scene, constellation, radius = 400) {
  const positions = {};
  for (const star of constellation.stars) {
    positions[star.id] = raDecToPosition(star.ra, star.dec, radius);
  }

  const points = [];
  for (const [a, b] of constellation.lines) {
    points.push(positions[a], positions[b]);
  }

  const geo = new THREE.BufferGeometry().setFromPoints(points);
  const mat = new THREE.LineBasicMaterial({
    color: 0x334466, transparent: true, opacity: 0.3,
    blending: THREE.AdditiveBlending, depthWrite: false,
  });
  return new THREE.LineSegments(geo, mat);
}
```

## Eclipse Configurations

### Solar Eclipse

Dramatic darkening with corona visible around the moon disc.

```javascript
const SOLAR_ECLIPSE = {
  moonOverlap: 1.0,          // 1.0 = total, 0.5 = partial
  coronaBrightness: 0.8,
  coronaColor: 0xeeeeff,
  skyDarkening: 0.9,          // Nearly night during totality
  horizonSunsetGlow: true,    // 360° sunset at horizon during totality
  diamondRing: true,          // Bright point as moon edge aligns
  rendering: `
    Position moon sprite directly over sun position. Add corona as a
    larger sprite behind moon with radial gradient and noise-modulated
    streamers. During totality, shift sky dome toward night colors and
    enable starfield at reduced brightness. The "diamond ring" effect
    is a single bright point at the moon's edge just before/after totality.
  `,
};
```

### Lunar Eclipse

Moon turns deep red-orange (Earth's atmosphere refracts red light onto moon).

```javascript
const LUNAR_ECLIPSE = {
  umbralCoverage: 1.0,        // 1.0 = total
  moonColor: 0x8b2500,        // Deep blood red
  penumbraColor: 0xcc6633,    // Orange-brown penumbra
  skyBrightening: false,      // Stars become more visible
  rendering: `
    Shift moon material's moonColor toward blood red. The lighting
    direction remains the same but the "sunlight" reaching the moon
    is filtered through Earth's atmosphere — only long wavelengths
    (red/orange) survive. The effect is eerie and beautiful.
  `,
};
```

## Sky Mood Profiles

Artistic direction for different emotional tones.

### Serene / Contemplative

```javascript
const SERENE = {
  starCount: 6000,
  starBrightness: 0.8,       // Slightly dimmed for softness
  milkyWay: 0.15,             // Subtle, not overwhelming
  nebulae: [],                // Clean, uncluttered
  moonPhase: 0.35,            // Crescent — delicate
  meteorRate: 0.05,           // Rare, special moments
  horizonGlow: 0.2,
  palette: 'Cool blues and silvers. No warm tones. Deep, still, quiet.',
};
```

### Awe / Cosmic Wonder

```javascript
const AWE = {
  starCount: 15000,
  starBrightness: 1.2,
  milkyWay: 0.4,              // Rich, prominent
  nebulae: ['orionNebula', 'pillarsOfCreation'],
  moonPhase: 0.0,             // New moon — darkest sky
  meteorRate: 0.3,
  horizonGlow: 0.05,
  palette: 'Maximum contrast. Vivid nebula colors against pure black. Stars should feel infinite.',
};
```

### Romantic / Warm

```javascript
const ROMANTIC = {
  starCount: 5000,
  starBrightness: 0.9,
  milkyWay: 0.1,
  nebulae: [],
  moonPhase: 0.5,             // Full moon — warm glow
  meteorRate: 0.1,            // Occasional shooting star wish
  horizonGlow: 0.4,           // Warm horizon
  palette: 'Warm moonlight. Horizon glows amber. Stars are soft, not sharp. Dreamy.',
};
```

### Ominous / Unsettling

```javascript
const OMINOUS = {
  starCount: 3000,
  starBrightness: 0.6,
  milkyWay: 0.05,
  nebulae: [{ type: 'dark', scale: 150 }],  // Large dark void
  moonPhase: 0.48,            // Almost full, slightly off
  moonTint: 0xffccaa,         // Slightly orange
  meteorRate: 0.0,
  horizonGlow: 0.1,
  palette: 'Desaturated. Dark nebula eats stars. Moon feels too close. Wrong and beautiful.',
};
```

### Fantasy / Dreamy

```javascript
const FANTASY = {
  starCount: 20000,
  starBrightness: 1.5,
  milkyWay: 0.5,              // Exaggerated, vivid
  nebulae: [
    { type: 'emission', colors: [0xff22aa, 0x22ffdd, 0xaa44ff], scale: 100 },
    { type: 'planetary', colors: [0x44ffaa, 0xff44aa, 0x4444ff], scale: 30 },
  ],
  moonPhase: 0.5,
  moonScale: 2.0,             // Oversized moon
  meteorRate: 0.5,
  horizonGlow: 0.3,
  palette: 'Over-saturated, larger-than-life. Break realism for beauty. More nebulae, more color, more magic.',
};
```

## Multi-Moon Configuration

For fantasy/sci-fi scenes with multiple moons.

```javascript
function createMultipleMoons(scene, moons) {
  // moons: array of { phase, elevation, azimuth, radius, color, distance }
  return moons.map(config => {
    const moon = new Moon(scene, {
      radius: config.radius ?? 8,
      distance: config.distance ?? 350,
    });
    moon.material.uniforms.moonColor.value.set(config.color ?? 0xf5f0e0);
    moon.setPhaseAndPosition(config.phase, config.elevation, config.azimuth);
    return moon;
  });
}

// Example: alien world with three moons
const alienMoons = [
  { phase: 0.3, elevation: 55, azimuth: -30, radius: 10, color: 0xf5f0e0 },
  { phase: 0.7, elevation: 30, azimuth: 45, radius: 5, color: 0xffccaa, distance: 380 },
  { phase: 0.1, elevation: 70, azimuth: 10, radius: 3, color: 0xccddff, distance: 420 },
];
```

---

```text
MIT License

Copyright (c) 2026 Kingsley

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
