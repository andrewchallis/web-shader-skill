# CK42BB procedural-weather-threejs

From [procedural-weather-threejs](https://github.com/CK42BB/procedural-weather-threejs), Kingsley (CK42BB), commit `26ad580`, MIT (notice at the end). Rain, snow, dust storms, ground fog, lightning, aurora, wet lens and frost overlays, a shared wind field, a weather state machine and a WGSL compute particle update. Teaching samples, not tested at Elsewhere's scales; read for ideas and port to TSL. Each original file follows unchanged.

---

<!-- file: SKILL.md -->

---
name: procedural-weather
description: >
  Generate dynamic procedural weather effects in Three.js using WebGPU compute with
  WebGL2 fallback. Covers rain (drizzle to monsoon), snow (flurries to blizzard), hail,
  fog and mist (ground fog, volumetric), lightning (bolt, sheet, cloud-internal),
  dust/sandstorms, wind-driven debris, rainbows, aurora borealis, and a weather state
  machine for smooth transitions. All precipitation uses GPU particle systems with
  collision, splashes, and accumulation. Provides per-effect lighting changes, ambient
  sound cue hints, and camera post-processing (wet lens, frost). Use when building
  weather systems, atmospheric effects, environmental ambience, climate simulation, or
  any scene needing dynamic weather. Triggers: "procedural weather", "rain effect",
  "snow particles", "lightning", "fog shader", "weather system", "storm", "blizzard",
  "sandstorm", "aurora", "rainbow", "precipitation", "weather transition", "wet lens".
---

# Procedural Weather

Dynamic, layered weather effects in Three.js — GPU particle precipitation, volumetric
fog, lightning, and smooth state transitions.

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│                Weather System                         │
│                                                      │
│  WeatherController (state machine)                   │
│    ├── current state + target state                  │
│    ├── transition progress (0→1)                     │
│    └── drives all subsystems:                        │
│                                                      │
│  ┌─ Precipitation ──────────────────────────────┐    │
│  │  GPU particles: rain, snow, hail             │    │
│  │  Ground splashes, accumulation               │    │
│  └──────────────────────────────────────────────┘    │
│  ┌─ Atmosphere ─────────────────────────────────┐    │
│  │  Fog, mist, dust, haze                       │    │
│  │  Volumetric (WebGPU) or exponential (WebGL)  │    │
│  └──────────────────────────────────────────────┘    │
│  ┌─ Electrical ─────────────────────────────────┐    │
│  │  Lightning bolts, sheet flashes              │    │
│  │  Cloud-internal illumination                 │    │
│  └──────────────────────────────────────────────┘    │
│  ┌─ Optical ────────────────────────────────────┐    │
│  │  Rainbows, aurora, god rays                  │    │
│  │  Wet lens, frost overlay                     │    │
│  └──────────────────────────────────────────────┘    │
│  ┌─ Environment ────────────────────────────────┐    │
│  │  Sky darkening, light color shift            │    │
│  │  Wind direction (shared across systems)      │    │
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
  }
  renderer.setSize(innerWidth, innerHeight);
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  return { renderer, gpuAvailable };
}
```

## Shared Wind System

Wind drives all weather subsystems — precipitation angle, fog drift, debris direction.

```javascript
class WindSystem {
  constructor() {
    this.direction = new THREE.Vector3(1, 0, 0.3).normalize();
    this.baseSpeed = 5;       // m/s
    this.gustSpeed = 0;
    this.gustFrequency = 0.5;
    this.turbulence = 0.1;
    this._time = 0;
  }

  update(dt) {
    this._time += dt;
    // Gusts: low-frequency intensity variation
    const gustEnvelope = Math.sin(this._time * this.gustFrequency) * 0.5 + 0.5;
    this.gustSpeed = gustEnvelope * this.baseSpeed * 0.6;
  }

  get speed() { return this.baseSpeed + this.gustSpeed; }

  // Wind force vector for particle displacement
  get force() {
    const s = this.speed;
    const turb = new THREE.Vector3(
      Math.sin(this._time * 2.3) * this.turbulence,
      0,
      Math.cos(this._time * 1.7) * this.turbulence
    );
    return this.direction.clone().multiplyScalar(s).add(turb);
  }
}
```

## Precipitation System

GPU particle system for rain, snow, and hail. Particles spawn in a box above the
camera, fall with gravity + wind, and recycle when below ground.

### Particle Buffer Layout

```javascript
function createPrecipitationBuffers(maxParticles) {
  // Each particle: vec4(x, y, z, life) + vec4(vx, vy, vz, size)
  const positions = new Float32Array(maxParticles * 4);
  const velocities = new Float32Array(maxParticles * 4);
  return { positions, velocities, count: maxParticles };
}
```

### Rain System

```javascript
class RainSystem {
  constructor(scene, options = {}) {
    this.scene = scene;
    this.count = options.count ?? 50000;
    this.spawnRadius = options.spawnRadius ?? 40;
    this.spawnHeight = options.spawnHeight ?? 30;
    this.dropLength = options.dropLength ?? 0.3;
    this.intensity = options.intensity ?? 1.0; // 0-1

    this._buildGeometry();
  }

  _buildGeometry() {
    // Each raindrop: a short line segment (2 vertices)
    const positions = new Float32Array(this.count * 6); // 2 verts × xyz
    const randoms = new Float32Array(this.count * 2);   // per-drop seed + phase

    for (let i = 0; i < this.count; i++) {
      const x = (Math.random() - 0.5) * this.spawnRadius * 2;
      const y = Math.random() * this.spawnHeight;
      const z = (Math.random() - 0.5) * this.spawnRadius * 2;

      // Top vertex
      positions[i * 6]     = x;
      positions[i * 6 + 1] = y;
      positions[i * 6 + 2] = z;
      // Bottom vertex (offset by drop length)
      positions[i * 6 + 3] = x;
      positions[i * 6 + 4] = y - this.dropLength;
      positions[i * 6 + 5] = z;

      randoms[i * 2]     = Math.random();     // seed
      randoms[i * 2 + 1] = Math.random();     // phase offset
    }

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geometry.setAttribute('aRandom', new THREE.BufferAttribute(randoms, 2, false, this.count));

    this.material = new THREE.ShaderMaterial({
      uniforms: {
        time:       { value: 0 },
        intensity:  { value: this.intensity },
        windForce:  { value: new THREE.Vector3() },
        gravity:    { value: -15.0 },
        spawnHeight: { value: this.spawnHeight },
        spawnRadius: { value: this.spawnRadius },
        dropLength: { value: this.dropLength },
        opacity:    { value: 0.35 },
        cameraPos:  { value: new THREE.Vector3() },
      },
      vertexShader: RAIN_VERT,     // See references/weather-shaders.md
      fragmentShader: RAIN_FRAG,   // See references/weather-shaders.md
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    });

    this.mesh = new THREE.LineSegments(geometry, this.material);
    this.mesh.frustumCulled = false;
    this.scene.add(this.mesh);
  }

  update(time, wind, cameraPos) {
    this.material.uniforms.time.value = time;
    this.material.uniforms.windForce.value.copy(wind.force);
    this.material.uniforms.cameraPos.value.copy(cameraPos);
    this.material.uniforms.intensity.value = this.intensity;
    // Recenter spawn box around camera
    this.mesh.position.x = cameraPos.x;
    this.mesh.position.z = cameraPos.z;
  }

  dispose() {
    this.scene.remove(this.mesh);
    this.mesh.geometry.dispose();
    this.material.dispose();
  }
}
```

### Snow System

Snow uses `Points` with per-particle flutter and tumble. Larger particles, slower fall,
more wind influence.

```javascript
class SnowSystem {
  constructor(scene, options = {}) {
    this.scene = scene;
    this.count = options.count ?? 20000;
    this.spawnRadius = options.spawnRadius ?? 50;
    this.spawnHeight = options.spawnHeight ?? 25;
    this.intensity = options.intensity ?? 1.0;

    this._build();
  }

  _build() {
    const positions = new Float32Array(this.count * 3);
    const seeds = new Float32Array(this.count * 3); // seed, phase, size

    for (let i = 0; i < this.count; i++) {
      positions[i * 3]     = (Math.random() - 0.5) * this.spawnRadius * 2;
      positions[i * 3 + 1] = Math.random() * this.spawnHeight;
      positions[i * 3 + 2] = (Math.random() - 0.5) * this.spawnRadius * 2;
      seeds[i * 3]     = Math.random();
      seeds[i * 3 + 1] = Math.random() * Math.PI * 2;
      seeds[i * 3 + 2] = 0.5 + Math.random() * 1.5; // size variation
    }

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geometry.setAttribute('aSeed', new THREE.BufferAttribute(seeds, 3));

    this.material = new THREE.ShaderMaterial({
      uniforms: {
        time:        { value: 0 },
        intensity:   { value: this.intensity },
        windForce:   { value: new THREE.Vector3() },
        gravity:     { value: -1.5 },
        spawnHeight: { value: this.spawnHeight },
        spawnRadius: { value: this.spawnRadius },
        flutterAmp:  { value: 2.0 },
        opacity:     { value: 0.85 },
        pointSize:   { value: 3.0 },
        cameraPos:   { value: new THREE.Vector3() },
      },
      vertexShader: SNOW_VERT,     // See references/weather-shaders.md
      fragmentShader: SNOW_FRAG,   // See references/weather-shaders.md
      transparent: true,
      depthWrite: false,
    });

    this.mesh = new THREE.Points(geometry, this.material);
    this.mesh.frustumCulled = false;
    this.scene.add(this.mesh);
  }

  update(time, wind, cameraPos) {
    this.material.uniforms.time.value = time;
    this.material.uniforms.windForce.value.copy(wind.force);
    this.material.uniforms.cameraPos.value.copy(cameraPos);
    this.material.uniforms.intensity.value = this.intensity;
    this.mesh.position.x = cameraPos.x;
    this.mesh.position.z = cameraPos.z;
  }

  dispose() {
    this.scene.remove(this.mesh);
    this.mesh.geometry.dispose();
    this.material.dispose();
  }
}
```

### Splash / Impact System

Ground splashes when rain hits surfaces — instanced ring sprites at impact points.

```javascript
class SplashSystem {
  constructor(scene, maxSplashes = 500) {
    this.scene = scene;
    this.max = maxSplashes;
    const geo = new THREE.PlaneGeometry(0.15, 0.15);
    geo.rotateX(-Math.PI / 2);

    this.material = new THREE.ShaderMaterial({
      uniforms: { time: { value: 0 } },
      vertexShader: SPLASH_VERT,
      fragmentShader: SPLASH_FRAG,
      transparent: true,
      depthWrite: false,
    });

    this.mesh = new THREE.InstancedMesh(geo, this.material, maxSplashes);
    this.mesh.frustumCulled = false;
    this.lifetimes = new Float32Array(maxSplashes);
    this.nextIdx = 0;
    this.scene.add(this.mesh);
  }

  spawn(position) {
    const dummy = new THREE.Object3D();
    dummy.position.copy(position);
    dummy.position.y += 0.01;
    dummy.scale.setScalar(0.5 + Math.random() * 0.5);
    dummy.updateMatrix();
    this.mesh.setMatrixAt(this.nextIdx, dummy.matrix);
    this.lifetimes[this.nextIdx] = 1.0;
    this.mesh.instanceMatrix.needsUpdate = true;
    this.nextIdx = (this.nextIdx + 1) % this.max;
  }

  update(dt) {
    for (let i = 0; i < this.max; i++) {
      if (this.lifetimes[i] > 0) {
        this.lifetimes[i] -= dt * 4; // ~0.25s lifetime
      }
    }
    this.material.uniforms.time.value += dt;
  }
}
```

## Fog & Atmosphere

### Exponential Fog (WebGL — built-in)

```javascript
function applyFog(scene, density = 0.01, color = 0xcccccc) {
  scene.fog = new THREE.FogExp2(color, density);
  scene.background = new THREE.Color(color);
}
```

### Ground Fog (Shader-based)

Height-attenuated fog that pools in valleys. Applied as a post-process or scene material.

```javascript
function createGroundFog(size = 200, maxHeight = 8) {
  const geo = new THREE.PlaneGeometry(size, size, 1, 1);
  geo.rotateX(-Math.PI / 2);

  const material = new THREE.ShaderMaterial({
    uniforms: {
      time:      { value: 0 },
      fogColor:  { value: new THREE.Color(0xdddddd) },
      maxHeight: { value: maxHeight },
      density:   { value: 0.8 },
      windDir:   { value: new THREE.Vector2(1, 0) },
      windSpeed: { value: 2.0 },
    },
    vertexShader: `
      varying vec3 vWorldPos;
      varying vec2 vUv;
      void main() {
        vWorldPos = (modelMatrix * vec4(position, 1.0)).xyz;
        vUv = uv;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: GROUND_FOG_FRAG, // See references/weather-shaders.md
    transparent: true,
    depthWrite: false,
    side: THREE.DoubleSide,
  });

  const mesh = new THREE.Mesh(geo, material);
  mesh.position.y = maxHeight * 0.5;
  mesh.renderOrder = 999;
  return mesh;
}
```

### Dust / Sandstorm

Dense particle field with color tinting and reduced visibility.

```javascript
function createDustStorm(scene, options = {}) {
  const count = options.count ?? 30000;
  const color = options.color ?? new THREE.Color(0xc4a060);
  const positions = new Float32Array(count * 3);
  const seeds = new Float32Array(count);

  for (let i = 0; i < count; i++) {
    positions[i * 3]     = (Math.random() - 0.5) * 80;
    positions[i * 3 + 1] = Math.random() * 15;
    positions[i * 3 + 2] = (Math.random() - 0.5) * 80;
    seeds[i] = Math.random();
  }

  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geo.setAttribute('aSeed', new THREE.BufferAttribute(seeds, 1));

  const material = new THREE.ShaderMaterial({
    uniforms: {
      time:      { value: 0 },
      dustColor: { value: color },
      windForce: { value: new THREE.Vector3(8, 0, 2) },
      opacity:   { value: 0.4 },
      pointSize: { value: 4.0 },
    },
    vertexShader: DUST_VERT,
    fragmentShader: DUST_FRAG,
    transparent: true,
    depthWrite: false,
    blending: THREE.NormalBlending,
  });

  const mesh = new THREE.Points(geo, material);
  mesh.frustumCulled = false;
  scene.add(mesh);
  return { mesh, material };
}
```

## Lightning System

Procedural branching lightning bolts with flash illumination.

```javascript
class LightningSystem {
  constructor(scene) {
    this.scene = scene;
    this.bolts = [];
    this.flashLight = new THREE.PointLight(0xccccff, 0, 500);
    this.flashLight.position.set(0, 80, 0);
    this.scene.add(this.flashLight);
    this._nextStrike = 2 + Math.random() * 8;
    this._flashDecay = 0;
  }

  // Generate a branching bolt path
  generateBolt(start, end, generations = 5, jitter = 15) {
    if (generations <= 0) return [start, end];

    const mid = start.clone().lerp(end, 0.4 + Math.random() * 0.2);
    const perpX = (Math.random() - 0.5) * jitter;
    const perpZ = (Math.random() - 0.5) * jitter;
    mid.x += perpX;
    mid.z += perpZ;

    const left = this.generateBolt(start, mid, generations - 1, jitter * 0.6);
    const right = this.generateBolt(mid, end, generations - 1, jitter * 0.6);

    // Branch: 30% chance at each midpoint
    let branch = [];
    if (Math.random() < 0.3 && generations > 2) {
      const branchEnd = mid.clone().add(
        new THREE.Vector3((Math.random() - 0.5) * jitter * 2, -jitter, (Math.random() - 0.5) * jitter * 2)
      );
      branch = this.generateBolt(mid, branchEnd, generations - 2, jitter * 0.4);
    }

    return [...left, ...right.slice(1), ...branch];
  }

  _createBoltMesh(points) {
    const positions = new Float32Array(points.length * 3);
    for (let i = 0; i < points.length; i++) {
      positions[i * 3]     = points[i].x;
      positions[i * 3 + 1] = points[i].y;
      positions[i * 3 + 2] = points[i].z;
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));

    const material = new THREE.LineBasicMaterial({
      color: 0xeeeeff,
      transparent: true,
      opacity: 1.0,
      linewidth: 2,
    });

    // Core bolt
    const line = new THREE.Line(geo, material);
    // Glow (wider, transparent)
    const glowMat = new THREE.LineBasicMaterial({
      color: 0x8888ff,
      transparent: true,
      opacity: 0.4,
      linewidth: 1,
    });
    const glow = new THREE.Line(geo.clone(), glowMat);
    glow.scale.setScalar(1.02);

    const group = new THREE.Group();
    group.add(line);
    group.add(glow);
    return { group, material, glowMat, life: 0.3 };
  }

  strike(origin, groundY = 0) {
    const start = origin ?? new THREE.Vector3(
      (Math.random() - 0.5) * 100, 70 + Math.random() * 30, (Math.random() - 0.5) * 100
    );
    const end = new THREE.Vector3(start.x + (Math.random() - 0.5) * 20, groundY, start.z + (Math.random() - 0.5) * 20);

    const points = this.generateBolt(start, end, 6, 12);
    const bolt = this._createBoltMesh(points);
    this.scene.add(bolt.group);
    this.bolts.push(bolt);

    // Flash
    this.flashLight.position.copy(start);
    this.flashLight.intensity = 15;
    this._flashDecay = 0.15;
  }

  update(dt, stormIntensity = 0.5) {
    // Auto-strike timing
    this._nextStrike -= dt;
    if (this._nextStrike <= 0 && stormIntensity > 0.3) {
      this.strike();
      this._nextStrike = (1 / stormIntensity) * (3 + Math.random() * 7);
    }

    // Fade bolts
    for (let i = this.bolts.length - 1; i >= 0; i--) {
      const bolt = this.bolts[i];
      bolt.life -= dt;
      const alpha = Math.max(bolt.life / 0.3, 0);
      bolt.material.opacity = alpha;
      bolt.glowMat.opacity = alpha * 0.4;
      if (bolt.life <= 0) {
        this.scene.remove(bolt.group);
        bolt.group.traverse(c => { if (c.geometry) c.geometry.dispose(); });
        this.bolts.splice(i, 1);
      }
    }

    // Flash decay
    if (this._flashDecay > 0) {
      this._flashDecay -= dt;
      this.flashLight.intensity *= 0.85;
    } else {
      this.flashLight.intensity = 0;
    }
  }

  dispose() {
    for (const bolt of this.bolts) {
      this.scene.remove(bolt.group);
    }
    this.scene.remove(this.flashLight);
  }
}
```

## Optical Effects

### Rainbow

Arc rendered as a screen-space shader overlay or a mesh arc in world space.

```javascript
function createRainbow(scene, sunDir) {
  const geo = new THREE.TorusGeometry(120, 3, 16, 64, Math.PI);
  const material = new THREE.ShaderMaterial({
    uniforms: {
      opacity: { value: 0.25 },
    },
    vertexShader: `
      varying vec2 vUv;
      void main() {
        vUv = uv;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: `
      varying vec2 vUv;
      uniform float opacity;
      void main() {
        float t = vUv.x;
        // ROYGBIV spectrum across the arc width
        vec3 col;
        if (t < 0.14)      col = vec3(1.0, 0.0, 0.0);
        else if (t < 0.28) col = vec3(1.0, 0.5, 0.0);
        else if (t < 0.42) col = vec3(1.0, 1.0, 0.0);
        else if (t < 0.57) col = vec3(0.0, 0.8, 0.0);
        else if (t < 0.71) col = vec3(0.0, 0.4, 1.0);
        else if (t < 0.85) col = vec3(0.3, 0.0, 0.8);
        else               col = vec3(0.5, 0.0, 0.5);
        // Soft edges
        float edge = smoothstep(0.0, 0.05, t) * smoothstep(1.0, 0.95, t);
        gl_FragColor = vec4(col, opacity * edge);
      }
    `,
    transparent: true,
    depthWrite: false,
    side: THREE.DoubleSide,
  });

  const rainbow = new THREE.Mesh(geo, material);
  // Position opposite to sun direction
  rainbow.position.set(-sunDir.x * 80, 20, -sunDir.z * 80);
  rainbow.rotation.z = Math.PI;
  rainbow.rotation.y = Math.atan2(-sunDir.x, -sunDir.z);
  scene.add(rainbow);
  return rainbow;
}
```

### Aurora Borealis

Undulating curtain of colored light using a displaced vertical plane.

```javascript
function createAurora(scene) {
  const geo = new THREE.PlaneGeometry(300, 40, 128, 16);
  const material = new THREE.ShaderMaterial({
    uniforms: {
      time: { value: 0 },
      color1: { value: new THREE.Color(0x00ff88) },
      color2: { value: new THREE.Color(0x4400ff) },
      color3: { value: new THREE.Color(0xff0066) },
    },
    vertexShader: AURORA_VERT,     // See references/weather-shaders.md
    fragmentShader: AURORA_FRAG,   // See references/weather-shaders.md
    transparent: true,
    depthWrite: false,
    side: THREE.DoubleSide,
    blending: THREE.AdditiveBlending,
  });

  const mesh = new THREE.Mesh(geo, material);
  mesh.position.set(0, 60, -100);
  mesh.rotation.x = -0.3;
  scene.add(mesh);
  return { mesh, material };
}
```

## Weather State Machine

Smooth transitions between weather states by interpolating all subsystem parameters.

```javascript
class WeatherController {
  constructor(scene, camera, wind) {
    this.scene = scene;
    this.camera = camera;
    this.wind = wind;
    this.rain = null;
    this.snow = null;
    this.lightning = null;
    this.fog = null;
    this.currentState = 'clear';
    this.targetState = 'clear';
    this.transition = 1.0;     // 1 = fully arrived at target
    this.transitionSpeed = 0.3; // 0→1 over ~3 seconds
  }

  setState(stateName) {
    if (stateName === this.currentState && this.transition >= 1) return;
    this.currentState = this.targetState;
    this.targetState = stateName;
    this.transition = 0;
  }

  update(dt) {
    this.wind.update(dt);

    if (this.transition < 1) {
      this.transition = Math.min(this.transition + dt * this.transitionSpeed, 1);
    }

    const t = this.transition;
    const from = WEATHER_STATES[this.currentState];
    const to = WEATHER_STATES[this.targetState];

    // Interpolate parameters
    const rainIntensity = lerp(from.rain, to.rain, t);
    const snowIntensity = lerp(from.snow, to.snow, t);
    const fogDensity = lerp(from.fogDensity, to.fogDensity, t);
    const stormIntensity = lerp(from.lightning, to.lightning, t);
    const skyDarkness = lerp(from.skyDarkness, to.skyDarkness, t);
    const windMult = lerp(from.windMultiplier, to.windMultiplier, t);

    this.wind.baseSpeed = 5 * windMult;

    // Update subsystems
    if (this.rain) {
      this.rain.intensity = rainIntensity;
      this.rain.update(performance.now() * 0.001, this.wind, this.camera.position);
    }
    if (this.snow) {
      this.snow.intensity = snowIntensity;
      this.snow.update(performance.now() * 0.001, this.wind, this.camera.position);
    }
    if (this.lightning) {
      this.lightning.update(dt, stormIntensity);
    }

    // Fog
    if (this.scene.fog) {
      this.scene.fog.density = fogDensity;
    }

    // Sky darkening
    const skyColor = new THREE.Color(0x87ceeb).lerp(new THREE.Color(0x333340), skyDarkness);
    if (this.scene.background instanceof THREE.Color) {
      this.scene.background.copy(skyColor);
    }
  }
}

function lerp(a, b, t) { return a + (b - a) * t; }

const WEATHER_STATES = {
  clear:      { rain: 0, snow: 0, fogDensity: 0.0005, lightning: 0, skyDarkness: 0, windMultiplier: 0.5 },
  cloudy:     { rain: 0, snow: 0, fogDensity: 0.002, lightning: 0, skyDarkness: 0.2, windMultiplier: 0.8 },
  drizzle:    { rain: 0.3, snow: 0, fogDensity: 0.004, lightning: 0, skyDarkness: 0.3, windMultiplier: 0.7 },
  rain:       { rain: 0.7, snow: 0, fogDensity: 0.006, lightning: 0.1, skyDarkness: 0.5, windMultiplier: 1.2 },
  heavyRain:  { rain: 1.0, snow: 0, fogDensity: 0.01, lightning: 0.3, skyDarkness: 0.7, windMultiplier: 1.8 },
  storm:      { rain: 1.0, snow: 0, fogDensity: 0.015, lightning: 0.8, skyDarkness: 0.85, windMultiplier: 2.5 },
  lightSnow:  { rain: 0, snow: 0.3, fogDensity: 0.003, lightning: 0, skyDarkness: 0.15, windMultiplier: 0.6 },
  snow:       { rain: 0, snow: 0.7, fogDensity: 0.006, lightning: 0, skyDarkness: 0.3, windMultiplier: 1.0 },
  blizzard:   { rain: 0, snow: 1.0, fogDensity: 0.025, lightning: 0, skyDarkness: 0.6, windMultiplier: 3.0 },
  fog:        { rain: 0, snow: 0, fogDensity: 0.03, lightning: 0, skyDarkness: 0.25, windMultiplier: 0.2 },
  sandstorm:  { rain: 0, snow: 0, fogDensity: 0.02, lightning: 0.1, skyDarkness: 0.5, windMultiplier: 3.0 },
};
```

## Camera Post-Processing

### Wet Lens Effect

Droplets on screen when raining, applied as a fullscreen overlay.

```javascript
function createWetLensOverlay(intensity = 0.5) {
  return new THREE.ShaderMaterial({
    uniforms: {
      time:      { value: 0 },
      intensity: { value: intensity },
      tScene:    { value: null },
    },
    vertexShader: FULLSCREEN_VERT,
    fragmentShader: WET_LENS_FRAG, // See references/weather-shaders.md
    transparent: true,
  });
}
```

### Frost Overlay

Progressive frost creep from screen edges during cold/blizzard conditions.

```javascript
function createFrostOverlay(intensity = 0.0) {
  return new THREE.ShaderMaterial({
    uniforms: {
      intensity: { value: intensity }, // 0=clear, 1=fully frosted
      time:      { value: 0 },
    },
    vertexShader: FULLSCREEN_VERT,
    fragmentShader: FROST_FRAG,
    transparent: true,
  });
}
```

## Complete Scene Assembly

```javascript
async function init() {
  const canvas = document.querySelector('#canvas');
  const { renderer } = await createRenderer(canvas);

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x87ceeb);
  scene.fog = new THREE.FogExp2(0x87ceeb, 0.001);

  const camera = new THREE.PerspectiveCamera(60, innerWidth / innerHeight, 0.5, 500);
  camera.position.set(0, 5, 20);

  const { OrbitControls } = await import('three/addons/controls/OrbitControls.js');
  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;

  // Ground
  const ground = new THREE.Mesh(
    new THREE.PlaneGeometry(200, 200),
    new THREE.MeshStandardMaterial({ color: 0x4a7c3f, roughness: 0.9 })
  );
  ground.rotation.x = -Math.PI / 2;
  ground.receiveShadow = true;
  scene.add(ground);

  // Lighting
  const sun = new THREE.DirectionalLight(0xfff4e5, 1.2);
  sun.position.set(30, 40, 20);
  scene.add(sun);
  scene.add(new THREE.HemisphereLight(0x87ceeb, 0x4a7c3f, 0.5));

  // Weather
  const wind = new WindSystem();
  const weather = new WeatherController(scene, camera, wind);
  weather.rain = new RainSystem(scene);
  weather.snow = new SnowSystem(scene);
  weather.lightning = new LightningSystem(scene);

  // Start with rain
  weather.setState('rain');

  const clock = new THREE.Clock();
  renderer.setAnimationLoop(() => {
    weather.update(clock.getDelta());
    controls.update();
    renderer.render(scene, camera);
  });

  window.addEventListener('resize', () => {
    camera.aspect = innerWidth / innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(innerWidth, innerHeight);
  });
}

init();
```

## Performance Guidelines

| Effect | Particle Count | Draw Calls | Notes |
|--------|---------------|------------|-------|
| Rain | 30K–80K | 1 (LineSegments) | Additive blend, no depth write |
| Snow | 10K–30K | 1 (Points) | Larger point size = fewer needed |
| Splashes | 200–500 | 1 (InstancedMesh) | Short lifetime, ring-buffer |
| Dust | 15K–40K | 1 (Points) | Camera-centered spawn box |
| Lightning | 1–3 bolts | 2–6 (Lines) | Ephemeral, negligible cost |
| Fog plane | 1 quad | 1 | Fragment-heavy, keep simple |
| Aurora | 1 plane | 1 | Vertex displacement only |

**Total budget**: All weather combined stays under 5 draw calls and ~100K particles.

**Key rules**:
- All animation in vertex shaders via uniforms (time, wind). Zero per-frame JS particle loops.
- `frustumCulled = false` on all particle meshes — spawn box follows camera.
- Recenter spawn box on camera each frame so particles always surround the viewer.
- `depthWrite: false` on all transparent weather effects to avoid sorting artifacts.

## Common Pitfalls

1. **Rain falls through roof**: Precipitation has no collision. For indoor scenes, cull particles below a Y threshold or use a height map mask uniform.
2. **Snow accumulation**: Not simulated per-particle. Use a ground plane shader that blends white coverage based on `snowIntensity * time`, or a decal system.
3. **Lightning too regular**: Randomize interval per `stormIntensity`. Real lightning is clustered — bursts of 2–3 strikes then silence.
4. **Fog and sky mismatch**: Always set `scene.fog.color` = `scene.background`. Mismatched colors create visible hard edges at the distance limit.
5. **Weather pops on/off**: Always use the state machine transition. Interpolating intensity from 0→target over 2–3 seconds looks natural.

## References

- `references/weather-shaders.md` — Complete GLSL vertex/fragment shaders for rain, snow, dust, ground fog, aurora, wet lens, frost, and WGSL compute particles.
- `references/weather-types.md` — Detailed profiles for 12 weather states with parameter tables, artistic direction, environmental effects, and combination rules.

---

<!-- file: weather-shaders.md -->

# Weather Shaders Reference

Complete shader implementations for all weather effects: rain, snow, dust, ground fog,
aurora, wet lens, frost overlay, and WGSL compute particles.

## Shared: Fullscreen Vertex Shader

```glsl
varying vec2 vUv;
void main() {
  vUv = uv;
  gl_Position = vec4(position.xy, 0.0, 1.0);
}
```

## Rain Shaders

### Vertex Shader

Animates raindrop positions with gravity + wind, wrapping around the spawn box.

```glsl
// rain.vert
attribute vec2 aRandom; // per-drop seed, phase

uniform float time;
uniform float intensity;
uniform vec3  windForce;
uniform float gravity;
uniform float spawnHeight;
uniform float spawnRadius;
uniform float dropLength;
uniform vec3  cameraPos;

varying float vAlpha;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void main() {
  float seed = aRandom.x;
  float phase = aRandom.y;

  // Determine if this is top (even) or bottom (odd) vertex of drop
  float vertIdx = mod(float(gl_VertexID), 2.0);

  vec3 pos = position;

  // Fall animation: wrap within spawn box
  float fallSpeed = gravity * (0.8 + seed * 0.4);
  float t = time + phase * 10.0;
  pos.y = mod(pos.y + fallSpeed * t, spawnHeight);

  // Wind displacement — increases with fall time
  float fallProgress = 1.0 - pos.y / spawnHeight;
  pos.x += windForce.x * fallProgress * 0.5;
  pos.z += windForce.z * fallProgress * 0.5;

  // Wrap horizontal
  pos.x = mod(pos.x + spawnRadius, spawnRadius * 2.0) - spawnRadius;
  pos.z = mod(pos.z + spawnRadius, spawnRadius * 2.0) - spawnRadius;

  // Bottom vertex offset (stretched by fall speed for motion blur)
  if (vertIdx > 0.5) {
    float stretch = dropLength * (1.0 + length(windForce) * 0.05);
    pos.y -= stretch;
    pos.x += windForce.x * 0.01;
  }

  // Fade out drops not active at current intensity
  vAlpha = step(seed, intensity) * 0.35;

  // Distance fade
  float dist = length(pos.xz);
  vAlpha *= smoothstep(spawnRadius, spawnRadius * 0.6, dist);

  gl_Position = projectionMatrix * modelViewMatrix * vec4(pos, 1.0);
}
```

### Fragment Shader

```glsl
// rain.frag
precision highp float;
uniform float opacity;
varying float vAlpha;

void main() {
  if (vAlpha < 0.01) discard;
  // Slight blue-white color
  gl_FragColor = vec4(0.7, 0.75, 0.9, vAlpha * opacity);
}
```

## Snow Shaders

### Vertex Shader

Flutter, tumble, and drift with sinusoidal paths.

```glsl
// snow.vert
attribute vec3 aSeed; // seed, phase, size

uniform float time;
uniform float intensity;
uniform vec3  windForce;
uniform float gravity;
uniform float spawnHeight;
uniform float spawnRadius;
uniform float flutterAmp;
uniform float pointSize;
uniform vec3  cameraPos;

varying float vAlpha;
varying float vSize;

void main() {
  float seed = aSeed.x;
  float phase = aSeed.y;
  float sizeVar = aSeed.z;

  vec3 pos = position;

  // Slow fall
  float fallSpeed = gravity * (0.6 + seed * 0.8);
  float t = time + phase * 8.0;
  pos.y = mod(pos.y + fallSpeed * t, spawnHeight);

  // Flutter: sinusoidal lateral drift
  float flutter = sin(t * (1.5 + seed * 2.0) + phase) * flutterAmp;
  float flutter2 = cos(t * (1.0 + seed * 1.5) + phase * 2.0) * flutterAmp * 0.7;
  pos.x += flutter + windForce.x * (1.0 - pos.y / spawnHeight) * 0.8;
  pos.z += flutter2 + windForce.z * (1.0 - pos.y / spawnHeight) * 0.8;

  // Wrap
  pos.x = mod(pos.x + spawnRadius, spawnRadius * 2.0) - spawnRadius;
  pos.z = mod(pos.z + spawnRadius, spawnRadius * 2.0) - spawnRadius;

  // Intensity gating
  vAlpha = step(seed, intensity) * 0.85;

  // Distance fade
  float dist = length(pos.xz);
  vAlpha *= smoothstep(spawnRadius, spawnRadius * 0.5, dist);

  vSize = sizeVar;

  vec4 mvPos = modelViewMatrix * vec4(pos, 1.0);
  gl_Position = projectionMatrix * mvPos;
  gl_PointSize = pointSize * sizeVar * (200.0 / -mvPos.z);
}
```

### Fragment Shader

Soft circular snowflake with slight sparkle.

```glsl
// snow.frag
precision highp float;
uniform float opacity;
varying float vAlpha;
varying float vSize;

void main() {
  if (vAlpha < 0.01) discard;

  // Circular soft point
  vec2 center = gl_PointCoord - 0.5;
  float dist = length(center);
  float alpha = smoothstep(0.5, 0.2, dist);

  // Subtle sparkle on larger flakes
  float sparkle = max(sin(dist * 20.0 + vSize * 10.0) * 0.15, 0.0);

  gl_FragColor = vec4(0.95 + sparkle, 0.97 + sparkle, 1.0, alpha * vAlpha * opacity);
}
```

## Dust / Sandstorm Shaders

### Vertex Shader

```glsl
// dust.vert
attribute float aSeed;

uniform float time;
uniform vec3  windForce;
uniform float pointSize;

varying float vAlpha;

void main() {
  vec3 pos = position;

  // Swirling motion
  float t = time + aSeed * 20.0;
  pos.x += windForce.x * t * 0.3 + sin(t * 2.0 + aSeed * 6.28) * 2.0;
  pos.z += windForce.z * t * 0.3 + cos(t * 1.5 + aSeed * 6.28) * 2.0;
  pos.y += sin(t * 3.0 + aSeed * 10.0) * 1.5;

  // Wrap
  float r = 40.0;
  pos.x = mod(pos.x + r, r * 2.0) - r;
  pos.z = mod(pos.z + r, r * 2.0) - r;
  pos.y = mod(pos.y, 15.0);

  vAlpha = 0.3 + aSeed * 0.3;

  vec4 mvPos = modelViewMatrix * vec4(pos, 1.0);
  gl_Position = projectionMatrix * mvPos;
  gl_PointSize = pointSize * (100.0 / -mvPos.z);
}
```

### Fragment Shader

```glsl
// dust.frag
precision highp float;
uniform vec3  dustColor;
uniform float opacity;
varying float vAlpha;

void main() {
  vec2 c = gl_PointCoord - 0.5;
  float d = length(c);
  float alpha = smoothstep(0.5, 0.15, d);
  gl_FragColor = vec4(dustColor, alpha * vAlpha * opacity);
}
```

## Ground Fog Fragment Shader

Height-attenuated volumetric fog using 2D noise for wisps.

```glsl
// ground_fog.frag
precision highp float;

uniform float time;
uniform vec3  fogColor;
uniform float maxHeight;
uniform float density;
uniform vec2  windDir;
uniform float windSpeed;

varying vec3 vWorldPos;
varying vec2 vUv;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1,0)), f.x),
             mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), f.x), f.y);
}

float fbm(vec2 p) {
  float sum = 0.0, amp = 1.0;
  for (int i = 0; i < 4; i++) {
    sum += noise(p) * amp;
    p *= 2.0; amp *= 0.5;
  }
  return sum / 1.875;
}

void main() {
  vec2 windOffset = windDir * windSpeed * time * 0.01;

  // Wispy noise pattern
  float n = fbm(vUv * 5.0 + windOffset);
  n = smoothstep(0.3, 0.7, n);

  // Height fade — densest at ground, gone at maxHeight
  float heightFade = 1.0 - smoothstep(0.0, maxHeight, vWorldPos.y);
  heightFade *= heightFade; // Quadratic falloff

  float alpha = n * heightFade * density;

  gl_FragColor = vec4(fogColor, alpha);
}
```

## Aurora Shaders

### Vertex Shader

Undulating curtain displacement.

```glsl
// aurora.vert
uniform float time;

varying vec2 vUv;
varying float vIntensity;

float noise(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
  vUv = uv;
  vec3 pos = position;

  // Curtain wave
  float wave1 = sin(pos.x * 0.02 + time * 0.3) * 8.0;
  float wave2 = sin(pos.x * 0.05 + time * 0.7) * 3.0;
  float wave3 = cos(pos.x * 0.03 + time * 0.15) * 5.0;
  pos.y += wave1 + wave2;
  pos.z += wave3;

  // Ruffle along curtain
  float ruffle = sin(pos.x * 0.1 + time * 1.5) * 2.0 * uv.y;
  pos.z += ruffle;

  // Intensity varies along curtain
  vIntensity = smoothstep(0.0, 0.3, uv.y) * smoothstep(1.0, 0.6, uv.y);
  vIntensity *= 0.5 + 0.5 * sin(pos.x * 0.03 + time * 0.2);

  gl_Position = projectionMatrix * modelViewMatrix * vec4(pos, 1.0);
}
```

### Fragment Shader

```glsl
// aurora.frag
precision highp float;

uniform vec3 color1; // Green
uniform vec3 color2; // Purple
uniform vec3 color3; // Pink

varying vec2 vUv;
varying float vIntensity;

void main() {
  // Color gradient along height
  vec3 col;
  if (vUv.y < 0.4) {
    col = mix(color2, color1, vUv.y / 0.4);
  } else if (vUv.y < 0.7) {
    col = mix(color1, color3, (vUv.y - 0.4) / 0.3);
  } else {
    col = mix(color3, color2, (vUv.y - 0.7) / 0.3);
  }

  // Horizontal variation
  float hVar = sin(vUv.x * 20.0) * 0.1 + 0.9;

  float alpha = vIntensity * hVar;
  alpha *= smoothstep(0.0, 0.1, vUv.y) * smoothstep(1.0, 0.85, vUv.y);

  gl_FragColor = vec4(col * 1.5, alpha * 0.6);
}
```

## Wet Lens Fragment Shader

Simulates rain droplets on the camera lens with refraction distortion.

```glsl
// wet_lens.frag
precision highp float;

uniform float time;
uniform float intensity; // 0-1
uniform sampler2D tScene;

varying vec2 vUv;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void main() {
  vec2 uv = vUv;
  vec4 sceneColor = texture2D(tScene, uv);

  if (intensity < 0.01) {
    gl_FragColor = sceneColor;
    return;
  }

  // Generate droplet pattern
  vec2 grid = floor(uv * 30.0);
  float droplet = 0.0;
  vec2 refractOffset = vec2(0.0);

  for (float dy = -1.0; dy <= 1.0; dy++) {
    for (float dx = -1.0; dx <= 1.0; dx++) {
      vec2 cell = grid + vec2(dx, dy);
      float h = hash(cell + floor(time * 0.5)); // Drops change over time
      if (h > 1.0 - intensity * 0.4) {
        vec2 dropPos = (cell + 0.5 + (hash(cell * 1.3) - 0.5) * 0.8) / 30.0;
        float dist = length(uv - dropPos);
        float radius = 0.005 + hash(cell * 2.7) * 0.01;
        float drop = smoothstep(radius, radius * 0.3, dist);
        droplet = max(droplet, drop);
        // Refraction: offset based on distance from drop center
        vec2 dir = normalize(uv - dropPos);
        refractOffset += dir * drop * 0.003;
      }
    }
  }

  // Streaks (running drops)
  float streak = hash(vec2(floor(uv.x * 60.0), 0.0));
  if (streak > 0.92 && intensity > 0.5) {
    float streakY = fract(uv.y * 3.0 - time * 0.2 + streak);
    float streakAlpha = smoothstep(0.0, 0.02, streakY) * smoothstep(0.15, 0.05, streakY);
    refractOffset.y += streakAlpha * 0.005;
    droplet = max(droplet, streakAlpha * 0.5);
  }

  vec4 refracted = texture2D(tScene, uv + refractOffset);
  vec4 result = mix(sceneColor, refracted, droplet);

  // Slight darkening from water film
  result.rgb *= 1.0 - intensity * 0.05;

  gl_FragColor = result;
}
```

## Frost Overlay Fragment Shader

Progressive frost creep from edges using noise.

```glsl
// frost.frag
precision highp float;

uniform float intensity; // 0=clear, 1=fully frosted
uniform float time;

varying vec2 vUv;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i+vec2(1,0)), f.x),
             mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), f.x), f.y);
}

float fbm(vec2 p) {
  float s = 0.0, a = 1.0;
  for (int i = 0; i < 5; i++) { s += noise(p) * a; p *= 2.0; a *= 0.5; }
  return s / 1.9375;
}

void main() {
  // Distance from screen edge
  vec2 centered = vUv * 2.0 - 1.0;
  float edgeDist = max(abs(centered.x), abs(centered.y));

  // Frost creeps from edges inward based on intensity
  float frostLine = mix(1.2, -0.2, intensity);
  float n = fbm(vUv * 15.0 + time * 0.02);
  float frost = smoothstep(frostLine, frostLine + 0.3, edgeDist + n * 0.3);

  // Crystal pattern
  float crystal = fbm(vUv * 40.0) * frost;
  float sparkle = max(sin(n * 50.0) * frost * 0.3, 0.0);

  vec3 frostColor = vec3(0.85, 0.9, 1.0) + sparkle;
  float alpha = frost * 0.7 + crystal * 0.2;

  gl_FragColor = vec4(frostColor, alpha);
}
```

## WGSL Compute: GPU Particle Update

Update all precipitation particles on the GPU each frame instead of relying on
vertex shader animation. Enables true collision detection and accumulation.

```wgsl
// particle_update.wgsl
struct Particle {
  pos: vec4<f32>,    // xyz + life
  vel: vec4<f32>,    // xyz + size
}

@group(0) @binding(0) var<storage, read_write> particles: array<Particle>;

struct Params {
  time: f32,
  dt: f32,
  gravity: f32,
  windX: f32,
  windZ: f32,
  spawnHeight: f32,
  spawnRadius: f32,
  groundY: f32,
  count: u32,
  intensity: f32,
}
@group(0) @binding(1) var<uniform> params: Params;

fn hash(n: f32) -> f32 {
  return fract(sin(n) * 43758.5453);
}

@compute @workgroup_size(256)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  if (gid.x >= params.count) { return; }

  var p = particles[gid.x];

  // Apply forces
  p.vel.y += params.gravity * params.dt;
  p.vel.x += (params.windX - p.vel.x) * params.dt * 0.5;
  p.vel.z += (params.windZ - p.vel.z) * params.dt * 0.5;

  // Integrate position
  p.pos.x += p.vel.x * params.dt;
  p.pos.y += p.vel.y * params.dt;
  p.pos.z += p.vel.z * params.dt;

  // Ground collision → respawn at top
  if (p.pos.y < params.groundY) {
    let seed = hash(f32(gid.x) + params.time);
    p.pos.x = (hash(seed * 127.1) - 0.5) * params.spawnRadius * 2.0;
    p.pos.y = params.spawnHeight + hash(seed * 311.7) * 5.0;
    p.pos.z = (hash(seed * 74.7) - 0.5) * params.spawnRadius * 2.0;
    p.vel = vec4<f32>(params.windX * 0.3, params.gravity * 0.5, params.windZ * 0.3, p.vel.w);
  }

  // Wrap horizontal
  let r = params.spawnRadius;
  p.pos.x = ((p.pos.x + r) % (r * 2.0)) - r;
  p.pos.z = ((p.pos.z + r) % (r * 2.0)) - r;

  // Intensity: disable particles by pushing off-screen
  if (hash(f32(gid.x)) > params.intensity) {
    p.pos.y = -1000.0;
  }

  particles[gid.x] = p;
}
```

## Performance Notes

- **Vertex shader animation** (rain/snow vert shaders): Zero CPU cost per particle — all via `time` + `mod()` wrapping. Preferred for WebGL path.
- **Compute particle update** (WGSL): Enables collision with heightmap and true accumulation. Use for WebGPU path when terrain interaction matters.
- **Additive blending** on rain avoids transparent sort cost but loses ability to darken. Use `NormalBlending` for snow/dust.
- **Point size attenuation**: `gl_PointSize = baseSize * (constant / -mvPosition.z)` — near particles larger, far particles smaller. Essential for depth.
- **Shader-defined strings**: Embed shaders as JS template literals or use import-map-compatible `.glsl` file loading.

---

<!-- file: weather-types.md -->

# Weather Types Reference

Detailed profiles for all weather states with parameter tables, artistic direction,
environmental effects, and combination rules.

## State Parameter Table

All values feed into the `WeatherController` state machine and its subsystems.

| State | Rain | Snow | Fog | Lightning | Sky Dark | Wind × | Character |
|-------|------|------|-----|-----------|----------|--------|-----------|
| clear | 0 | 0 | 0.0005 | 0 | 0 | 0.5 | Calm, blue sky |
| cloudy | 0 | 0 | 0.002 | 0 | 0.2 | 0.8 | Overcast, flat light |
| drizzle | 0.3 | 0 | 0.004 | 0 | 0.3 | 0.7 | Gentle, misty |
| rain | 0.7 | 0 | 0.006 | 0.1 | 0.5 | 1.2 | Steady downpour |
| heavyRain | 1.0 | 0 | 0.01 | 0.3 | 0.7 | 1.8 | Torrential, loud |
| storm | 1.0 | 0 | 0.015 | 0.8 | 0.85 | 2.5 | Violent, dramatic |
| lightSnow | 0 | 0.3 | 0.003 | 0 | 0.15 | 0.6 | Peaceful, gentle |
| snow | 0 | 0.7 | 0.006 | 0 | 0.3 | 1.0 | Steady, muffled |
| blizzard | 0 | 1.0 | 0.025 | 0 | 0.6 | 3.0 | Whiteout, fierce |
| fog | 0 | 0 | 0.03 | 0 | 0.25 | 0.2 | Still, mysterious |
| sandstorm | 0 | 0 | 0.02 | 0.1 | 0.5 | 3.0 | Abrasive, orange |
| aurora | 0 | 0 | 0.001 | 0 | 0 | 0.3 | Clear night, polar |

## Weather State Profiles

### Clear

**Character**: Calm blue sky, bright directional sun, minimal atmosphere.

```javascript
const CLEAR = {
  sky: {
    zenithColor: 0x1a6abf,
    horizonColor: 0x87ceeb,
    sunIntensity: 1.5,
    ambientIntensity: 0.4,
  },
  particles: { rain: 0, snow: 0, dust: 0 },
  atmosphere: { fogDensity: 0.0005, fogColor: 0x87ceeb },
  wind: { base: 2, gustFrequency: 0.2, gustAmplitude: 0.3 },
  camera: { wetLens: 0, frost: 0 },
  artistic: `
    The baseline. Maximum visibility, sharp shadows, vibrant colors.
    Atmosphere is barely perceptible — just enough haze at the horizon
    to suggest distance. Wind is a gentle breeze. Grass sways slowly.
    Birds optional. The scene should feel open and inviting.
  `,
};
```

### Drizzle

**Character**: Light misty rain, diffused light, everything slightly softened.
Contemplative, quiet.

```javascript
const DRIZZLE = {
  sky: {
    zenithColor: 0x6688aa,
    horizonColor: 0x99aabb,
    sunIntensity: 0.6,
    ambientIntensity: 0.5,   // Ambient goes up as sun diffuses
  },
  particles: {
    rain: 0.3,
    dropLength: 0.15,        // Shorter drops — smaller droplets
    dropOpacity: 0.2,        // More transparent
    splashChance: 0.1,       // Fewer visible splashes
  },
  atmosphere: {
    fogDensity: 0.004,
    fogColor: 0xaabbcc,
    groundFog: 0.3,          // Slight mist at ground level
  },
  wind: { base: 3, gustFrequency: 0.3, gustAmplitude: 0.2 },
  camera: { wetLens: 0.15, frost: 0 },
  artistic: `
    Soft, gentle, almost romantic. The world feels slightly out of focus.
    Light is flat and diffused — no harsh shadows. Colors are muted but
    not grey. Think "walking in a light mist." The wet lens effect should
    be barely noticeable — just occasional tiny droplets. Sound would be
    a soft patter, barely audible over ambient noise.
  `,
};
```

### Rain

**Character**: Steady moderate rainfall, puddles forming, distinct sound of rain.
The classic "rainy day."

```javascript
const RAIN = {
  sky: {
    zenithColor: 0x445566,
    horizonColor: 0x778899,
    sunIntensity: 0.3,
    ambientIntensity: 0.5,
  },
  particles: {
    rain: 0.7,
    dropLength: 0.3,
    dropOpacity: 0.35,
    splashChance: 0.4,
    splashScale: 1.0,
  },
  atmosphere: {
    fogDensity: 0.006,
    fogColor: 0x889999,
    groundFog: 0.1,
  },
  wind: { base: 6, gustFrequency: 0.5, gustAmplitude: 0.6 },
  camera: { wetLens: 0.4, frost: 0 },
  environment: {
    surfaceWetness: 0.6,     // Darken ground, increase specular
    puddleCoverage: 0.2,    // Reflective patches on ground
  },
  artistic: `
    Clearly raining — you'd grab an umbrella. Distinct angled streaks
    visible against dark surfaces. Ground develops a wet sheen. Occasional
    distant rumble suggests a broader system. Visibility reduced but still
    good. Reflections become important — wet surfaces mirror the sky.
    Wind angles the rain noticeably.
  `,
};
```

### Heavy Rain

**Character**: Intense downpour, reduced visibility, percussive splashes,
approaching storm energy.

```javascript
const HEAVY_RAIN = {
  sky: {
    zenithColor: 0x2a3344,
    horizonColor: 0x556677,
    sunIntensity: 0.15,
    ambientIntensity: 0.4,
  },
  particles: {
    rain: 1.0,
    dropLength: 0.4,
    dropOpacity: 0.4,
    splashChance: 0.7,
    splashScale: 1.3,
  },
  atmosphere: {
    fogDensity: 0.01,
    fogColor: 0x667788,
    groundFog: 0.0,          // Washed away by rain
  },
  wind: { base: 10, gustFrequency: 0.8, gustAmplitude: 1.2 },
  camera: { wetLens: 0.65, frost: 0 },
  environment: {
    surfaceWetness: 0.9,
    puddleCoverage: 0.5,
    occasionalLightning: true,
  },
  artistic: `
    Dramatic and immersive. Rain is visible as a curtain — you can see
    wave-like intensities sweep across the field. Splashes bounce visibly
    off every surface. Visibility drops to maybe 60 meters. Wind drives
    the rain at a strong angle. Occasional distant lightning flickers
    illuminate the clouds briefly. The world feels urgent and powerful.
  `,
};
```

### Storm

**Character**: Full thunderstorm. Dark sky, violent wind, frequent lightning.
Maximum drama.

```javascript
const STORM = {
  sky: {
    zenithColor: 0x1a1a2e,
    horizonColor: 0x333344,
    sunIntensity: 0.05,
    ambientIntensity: 0.25,
  },
  particles: {
    rain: 1.0,
    dropLength: 0.5,
    dropOpacity: 0.4,
    splashChance: 0.9,
    splashScale: 1.5,
  },
  atmosphere: {
    fogDensity: 0.015,
    fogColor: 0x334455,
  },
  lightning: {
    intensity: 0.8,
    minInterval: 2,
    maxInterval: 8,
    boltBranching: 6,
    flashDuration: 0.15,
    flashIntensity: 15,
    clusterBursts: true,     // 2-3 quick strikes then pause
  },
  wind: { base: 15, gustFrequency: 1.2, gustAmplitude: 2.5 },
  camera: { wetLens: 0.8, frost: 0 },
  artistic: `
    Awe-inspiring and slightly terrifying. The sky is near-black between
    lightning flashes. When lightning fires, everything turns blue-white
    for an instant — shadows flip direction. Thunder would shake the
    ground. Rain is almost horizontal in the strongest gusts. Trees (if
    present) bend dramatically. This is the cinematic storm scene — hold
    nothing back. The contrast between darkness and lightning flash is key.
  `,
};
```

### Light Snow

**Character**: Gentle, peaceful snowfall. Each flake visible. Quiet.

```javascript
const LIGHT_SNOW = {
  sky: {
    zenithColor: 0x7788aa,
    horizonColor: 0xaabbcc,
    sunIntensity: 0.5,
    ambientIntensity: 0.6,   // Snow reflects a lot of ambient
  },
  particles: {
    snow: 0.3,
    flakeSize: 2.5,
    flutterAmplitude: 2.0,
    fallSpeed: -1.2,
    sparkle: true,           // Flakes catch light
  },
  atmosphere: {
    fogDensity: 0.003,
    fogColor: 0xccccdd,
  },
  wind: { base: 2, gustFrequency: 0.3, gustAmplitude: 0.4 },
  camera: { wetLens: 0, frost: 0.05 },
  environment: {
    groundWhiteness: 0.2,    // Dusting of snow
  },
  artistic: `
    Magical and serene. Individual flakes drift lazily, catching light
    as they tumble. You can follow a single flake's path. The world
    gets slightly quieter — snow absorbs sound. Colors desaturate slightly.
    A thin dusting of white begins on horizontal surfaces. Think "first
    snow of the season" — wonder and calm.
  `,
};
```

### Snow

**Character**: Steady snowfall, accumulating, the world transforming white.

```javascript
const SNOW = {
  sky: {
    zenithColor: 0x667788,
    horizonColor: 0x99aabb,
    sunIntensity: 0.3,
    ambientIntensity: 0.6,
  },
  particles: {
    snow: 0.7,
    flakeSize: 3.0,
    flutterAmplitude: 1.5,
    fallSpeed: -1.8,
  },
  atmosphere: {
    fogDensity: 0.006,
    fogColor: 0xbbbbcc,
  },
  wind: { base: 5, gustFrequency: 0.5, gustAmplitude: 0.8 },
  camera: { wetLens: 0, frost: 0.15 },
  environment: {
    groundWhiteness: 0.6,
  },
  artistic: `
    Immersive snowfall. Dense enough that the sky disappears into white.
    The ground is clearly covered. Everything feels muffled and insulated.
    Visibility is reduced — distant objects fade into white. The light is
    flat, directionless. Frost starts creeping at the edges of the lens.
  `,
};
```

### Blizzard

**Character**: Whiteout conditions. Nearly zero visibility, fierce wind,
survival weather.

```javascript
const BLIZZARD = {
  sky: {
    zenithColor: 0x778899,
    horizonColor: 0xaabbcc,
    sunIntensity: 0.1,
    ambientIntensity: 0.5,
  },
  particles: {
    snow: 1.0,
    flakeSize: 4.0,
    flutterAmplitude: 0.5,   // Low — wind overpowers flutter
    fallSpeed: -2.5,
  },
  atmosphere: {
    fogDensity: 0.025,
    fogColor: 0xccccdd,
  },
  wind: { base: 20, gustFrequency: 1.5, gustAmplitude: 3.0 },
  camera: { wetLens: 0, frost: 0.6 },
  artistic: `
    Hostile and disorienting. Snow moves nearly horizontally. Visibility
    drops to 5-10 meters. The world is a white void with vague shapes.
    The camera frosts heavily — only the center remains clear. Wind
    noise would dominate everything. This is weather as antagonist.
  `,
};
```

### Fog

**Character**: Still, mysterious, intimate. The world shrinks to a small bubble.

```javascript
const FOG = {
  sky: {
    zenithColor: 0x99aabb,
    horizonColor: 0xbbccdd,
    sunIntensity: 0.2,
    ambientIntensity: 0.6,
  },
  particles: { rain: 0, snow: 0, dust: 0 },
  atmosphere: {
    fogDensity: 0.03,
    fogColor: 0xcccccc,
    groundFog: 0.9,
    groundFogHeight: 6,
  },
  wind: { base: 0.5, gustFrequency: 0.1, gustAmplitude: 0.1 },
  camera: { wetLens: 0.05, frost: 0 },
  artistic: `
    Atmospheric and contemplative. Objects emerge from and disappear
    into the white. Sounds feel close and muffled. Light is completely
    diffused — no shadows, no direction. Ground fog pools in low areas
    and drifts slowly. Trees are silhouettes. The mood is dreamlike
    and slightly eerie. Beautiful for close-up intimate scenes.
  `,
};
```

### Sandstorm

**Character**: Harsh, abrasive, orange-tinted. Desert survival weather.

```javascript
const SANDSTORM = {
  sky: {
    zenithColor: 0x8b6b3a,
    horizonColor: 0xc4a060,
    sunIntensity: 0.3,       // Sun visible as dim disc
    ambientIntensity: 0.4,
  },
  particles: {
    dust: 1.0,
    dustColor: 0xc4a060,
    dustSize: 4.0,
    dustOpacity: 0.45,
  },
  atmosphere: {
    fogDensity: 0.02,
    fogColor: 0xc4a060,      // Match dust color
  },
  wind: { base: 20, gustFrequency: 1.0, gustAmplitude: 3.0 },
  camera: { wetLens: 0, frost: 0 },
  environment: {
    colorTint: 0xc4a060,     // Everything shifts orange/brown
    tintStrength: 0.3,
  },
  artistic: `
    The entire world shifts to a warm orange-brown palette. Dust
    particles swirl in visible eddies. The sun is a dim disc behind
    the haze. Visibility drops to 15-20 meters. Horizontal wind drives
    particles in visible streams close to the ground. Static electricity
    can produce occasional lightning within the dust cloud. Abrasive
    and hostile, but with a stark beauty.
  `,
};
```

### Aurora

**Character**: Clear polar night with northern lights. Serene, magical.

```javascript
const AURORA = {
  sky: {
    zenithColor: 0x050515,
    horizonColor: 0x0a0a2a,
    sunIntensity: 0,         // Night
    ambientIntensity: 0.15,
    starField: true,
  },
  particles: { rain: 0, snow: 0, dust: 0 },
  atmosphere: {
    fogDensity: 0.001,
    fogColor: 0x050515,
  },
  aurora: {
    enabled: true,
    colors: [0x00ff88, 0x4400ff, 0xff0066],
    waveSpeed: 0.3,
    curtainHeight: 40,
    curtainWidth: 300,
    intensity: 0.6,
  },
  wind: { base: 1, gustFrequency: 0.1, gustAmplitude: 0.2 },
  camera: { wetLens: 0, frost: 0.02 },
  artistic: `
    Dark clear sky filled with stars. The aurora is the star — an
    undulating curtain of green, purple, and pink light rippling across
    the sky. The light is reflected faintly on water or snow below.
    Everything is still and quiet. The mood is wonder and smallness
    before cosmic beauty. Use additive blending for the curtain glow.
  `,
};
```

## Transition Rules

Not all weather transitions make physical sense. Use this matrix for valid
direct transitions (✓ = natural, ~ = possible but abrupt):

```
           → clear cloudy drizzle rain heavy storm lSnow snow bliz fog sand aurora
clear      │  ─     ✓      ✓      ~    ✗     ✗     ✓     ~    ✗    ✓   ~    ✓
cloudy     │  ✓     ─      ✓      ✓    ~     ✗     ✓     ✓    ✗    ✓   ✗    ✗
drizzle    │  ✓     ✓      ─      ✓    ✓     ✗     ✗     ✗    ✗    ✓   ✗    ✗
rain       │  ~     ✓      ✓      ─    ✓     ✓     ✗     ✗    ✗    ~   ✗    ✗
heavy      │  ✗     ~      ✓      ✓    ─     ✓     ✗     ✗    ✗    ✗   ✗    ✗
storm      │  ✗     ✗      ✗      ✓    ✓     ─     ✗     ✗    ✗    ✗   ✗    ✗
lSnow      │  ✓     ✓      ✗      ✗    ✗     ✗     ─     ✓    ~    ✓   ✗    ✓
snow       │  ~     ✓      ✗      ✗    ✗     ✗     ✓     ─    ✓    ~   ✗    ✗
blizzard   │  ✗     ✗      ✗      ✗    ✗     ✗     ~     ✓    ─    ✗   ✗    ✗
fog        │  ✓     ✓      ✓      ~    ✗     ✗     ✓     ~    ✗    ─   ✗    ✗
sandstorm  │  ~     ✗      ✗      ✗    ✗     ✗     ✗     ✗    ✗    ✗   ─    ✗
aurora     │  ✓     ✗      ✗      ✗    ✗     ✗     ✓     ✗    ✗    ✗   ✗    ─
```

For transitions marked ✗, route through an intermediate state:
- storm → clear: go storm → rain → cloudy → clear
- blizzard → clear: go blizzard → snow → lightSnow → clear

```javascript
function findTransitionPath(from, to) {
  const ROUTES = {
    'storm→clear':     ['rain', 'cloudy', 'clear'],
    'blizzard→clear':  ['snow', 'lightSnow', 'clear'],
    'clear→storm':     ['cloudy', 'rain', 'heavyRain', 'storm'],
    'clear→blizzard':  ['lightSnow', 'snow', 'blizzard'],
    'sandstorm→rain':  ['sandstorm→clear', 'cloudy', 'drizzle', 'rain'],
  };
  const key = `${from}→${to}`;
  return ROUTES[key] ?? [to]; // Direct if no route defined
}
```

## Biome Presets

Quick weather configurations appropriate for different environments.

```javascript
const BIOME_WEATHER = {
  temperate: {
    defaultState: 'cloudy',
    probabilities: { clear: 0.3, cloudy: 0.25, drizzle: 0.15, rain: 0.15, fog: 0.1, storm: 0.05 },
    transitionMinutes: [15, 45], // Weather changes every 15-45 min
  },
  tropical: {
    defaultState: 'clear',
    probabilities: { clear: 0.35, cloudy: 0.15, rain: 0.2, heavyRain: 0.15, storm: 0.1, fog: 0.05 },
    transitionMinutes: [5, 20],  // Tropical weather changes fast
  },
  desert: {
    defaultState: 'clear',
    probabilities: { clear: 0.7, cloudy: 0.1, sandstorm: 0.15, fog: 0.05 },
    transitionMinutes: [30, 120],
  },
  boreal: {
    defaultState: 'cloudy',
    probabilities: { clear: 0.15, cloudy: 0.2, lightSnow: 0.2, snow: 0.2, blizzard: 0.1, fog: 0.1, aurora: 0.05 },
    transitionMinutes: [20, 60],
  },
  savanna: {
    defaultState: 'clear',
    probabilities: { clear: 0.5, cloudy: 0.2, drizzle: 0.1, heavyRain: 0.1, sandstorm: 0.1 },
    transitionMinutes: [20, 90],
  },
};
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
