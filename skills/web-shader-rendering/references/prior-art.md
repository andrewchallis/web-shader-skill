
## WeebLabs Nightscape (Three.js r128, WebGL2)

[Nightscape](https://github.com/WeebLabs/Nightscape), a night flight over a
moonlit cloud sea in one `index.html`. **No licence file**, so treat it as
all rights reserved: ideas only, don't copy code. Its README section "How it
renders" is the best short write-up we've found on keeping ray-marched
clouds still while the camera moves.

Take from it:

- **World-anchored sample planes**: view rays sample on planes fixed in the
  world, not at distances from the camera, so flying never slides sample
  slices through a cloud. Spacing doubles in distance bands (5, 10, 20...
  units); over the far half of each band every other plane fades out, and
  a sample past a band edge snaps to the coarser grid. Near a surface, drop
  to planes twice as fine.
- **Edges widen with distance**: the density ramp at cloud edges gets wider
  further away, so tiny shifts of thin far wisps don't flip opacity.
- **No per-frame randomness in the clouds**: with the camera still,
  consecutive frames are identical. Noise is removed by temporal
  accumulation that reprojects with a cloud depth, clamps history to the
  3x3 neighbourhood and leans on the new frame where motion is fast.
- **Bake what doesn't move**: optical depth towards the light (a long
  march), optical depth straight up (ambient occlusion) and the cloud SDF
  into one tiling 3D texture, baked in chunks over several frames. At
  run time: one texture read in clear air, which also gives a safe skip
  distance, plus one live octave of billow. About 5x cheaper. Two crisp
  local light samples keep edges sharp; the bake covers the rest.
- **Skip conservatively**: only a fifth of the baked distance, because the
  field changes faster than true distance near anvils.
- **Soft far limit**: cloud fades out over the last stretch of the march so
  whole slabs never pop in.
- Adaptive resolution (26 to 80% of the window) from frame times with wide
  hysteresis, and history carried across resolution changes.
- Lighting: Beer-Lambert, dual-lobe Henyey-Greenstein, three-octave
  multiple scattering, powder, height- and occlusion-weighted ambient,
  haze thinning with height.

## Orbit to close Earth views: 3dsolarsystem.online

[3dsolarsystem.online](https://3dsolarsystem.online/viewer/#/earth)
(Polyxmedia / Voidmode Studios), Three.js WebGL. Its deployed bundle exposes
original modules through a source map; that does not grant permission to
copy the proprietary implementation. Ideas only. The normal viewer enforces
about 2 km clearance above the displaced surface. Its separate rocketry
mode has local ground terrain; do not describe normal zoom as worldwide
street-level terrain.

- Surface imagery uses a bounded atlas and sparse page tables: 512 px
  tiles, Landsat through level 11, Sentinel-2 composed onto level 12
  (roughly 15 m/px at the equator). Coarse imagery remains available while
  finer tiles load.
- Clouds use the same weather coordinates and clock across the globe and
  local volume. The globe combines real cloud coverage, streamed 1 km
  pages and footprint-filtered procedural cloud tops. Below 200 km,
  supported quality tiers introduce volumes, reaching full weight by
  100 km. The cloud maps and volume agree before they blend.
- A camera-relative local pass in Earth-fixed metres renders close-view
  atmosphere and clouds. Do not confuse this with the rocketry mode's
  site-centred ground patches.
- Rocketry's ground uses nested curved grids, local site detail and
  procedural coastal relief; this is not evidence of a worldwide
  high-resolution Earth elevation model.

Read [Earth surface streaming](earth-surface-streaming.md) for tile
selection, imagery composition, camera handling, atmosphere and terrain
limits, including a dated comparison with an existing implementation.

Read [Earth cloud transitions](earth-cloud-transitions.md) for the verified
cloud modules, exact example settings, blending constraints and motion
checks. The transferable lesson is shared fields and consistent filtering,
rather than copying one renderer's altitude thresholds.

## takram three-clouds (MIT, GLSL)

[@takram/three-clouds](https://github.com/takram-design-engineering/three-geospatial/tree/main/packages/clouds)
(three-geospatial, checked at `b012ad06`, May 2026, MIT, Shota Matsuda):
geospatial volumetric clouds over a real-size Earth for Three.js. The README
says "nothing novel here, just a combination of existing techniques", and
that is its value: a clean, measured reference pipeline. Still GLSL
post-processing; TSL and WebGPU are planned, not done.

Take from it:

- **Up to four cloud layers in one march**: each layer's coverage sits in
  one channel (r, g, b, a) of the weather texture and all four are
  evaluated together as a `vec4`. Each layer has its own altitude, height,
  density scale, shape and detail amounts, weather exponent and density
  profile. This is the "cloud types as height bands in one march" idea
  from [cloud-types.md](cloud-types.md), already built: low cumulus, a mid
  deck and a thin high layer (e.g. `densityScale 0.003`, no detail) cost
  one march, not three.
- **Beer shadow maps**: march the clouds once from the Sun's orthographic
  view, store what's needed to rebuild optical depth along the Sun ray,
  then the camera march reads it instead of a light march per sample.
  The shadow map gets its own temporal filtering to hide its jitter.
- **Temporal upscale**: the cloud pass marches 1/16 of the pixels and a
  TAAU-like resolve fills the rest. Their own numbers: on an M3 Max at 4K
  "High", 92-95 fps with it and 31 without. Known costs: ghosting and
  smearing through sparse cloud and at disocclusions.
- **Quality presets** (Low: no shape detail, light shafts or turbulence,
  coarser march; Medium: no shafts or turbulence; High; Ultra: bigger
  shadow map). A clean model for a desktop and laptop preset split.
- Cost grows with total layer height, and heavy erosion wastes samples on
  rays that miss the cloud. Their suggested fix: use last frame's front
  depth and sample count, reprojected, to narrow this frame's march range.
- Aerial perspective is applied with one transmittance-weighted mean
  cloud depth per pixel: cheap, but wrong where far sparse clouds overlap.
- Known gaps worth knowing before borrowing: weather tiled on a cube
  sphere shows seams; every layer's base sits at one height and looks
  artificial; no views from space yet.

## joshbrew WebGPU noise textures and volumetric clouds (MIT)

[webgpu_noise_compute_textures](https://github.com/joshbrew/webgpu_noise_compute_textures)
(checked at `c0b25edb`, 5 Nov 2026, MIT; [demo](http://webgpunoise.netlify.app/))
is a raw WebGPU (WGSL compute, no Three.js) noise toolkit. It now also holds
the author's volumetric cloud renderer under `tools/clouds/` (the older
[webgpu_realtime_clouds](https://github.com/joshbrew/webgpu_realtime_clouds)
repo; [demo](https://webgpuclouds.netlify.app/)) and a GPU planet mesh path
under `tools/planet/`. MIT, so code may be ported with the licence notice;
it still has to be rewritten as TSL to run in Three.js.

Take from it:

- **Toroidal 3D volumes from 4D noise**: a seamless tiling 3D texture is
  made by sampling 4D noise on two circles (see its toroidal explainer,
  `tools/noise/toroidal_explainer.html`). Kernels for Perlin, Worley,
  cellular, billow, FBM and Voronoi blends all come in 4D form. Use this
  when a baked cloud or gas volume must tile with no seam.
- **One compute entry point per kernel** (about 90: Perlin, billow, ridged
  multifractal, FBM, Worley/cellular, Voronoi variants, curl, domain warp,
  Gabor, foam, terrace, blue noise, normals, Gaussian blur), stacked in
  ordered passes onto a cleared target. Separate entry points compile fast,
  and only the chosen ones build pipelines.
- Big textures are split into tiles (2D) or chunks (3D) under a size cap,
  with ping-pong storage and explicit disposal.
- **Cloud renderer** (`tools/clouds/clouds.js`, `CloudComputeBuilder`): a
  compute pass that marches a world box using weather, shape and detail
  textures plus blue noise, with weather-column empty skipping, per-column
  height bounds from the weather map, an early out for rays that miss the
  cloud band, adaptive steps in thick boxes, a cheaper "far proxy" sample
  for small far clouds, and temporal interleave (only a subset of pixels
  marched each frame, history copied forward).
- **Planet clouds** (`planetClouds.js`, `planetCloudNoise.js`,
  `shaders/cloudPlanet.wgsl`, `planetGasAppearance.wgsl`): a styled planet
  raymarch layer, baked gas curl for weather motion and a shared gas-giant
  palette. Worth reading before more Jupiter or Saturn deck work.
- Its tests check weather continuity across phase joins and wind-cell
  boundaries, with a deliberately broken baseline that must fail: a good
  pattern for proving a pop is gone.

## CK42BB procedural clouds skill (MIT)

[procedural-clouds-threejs](https://github.com/CK42BB/procedural-clouds-threejs)
(checked at `fb4a1b22`, Feb 2026, MIT) is a Claude Code skill for Three.js
sky clouds: a volumetric raymarch on WebGPU, instanced soft-sphere clusters
and billboards as WebGL2 fallbacks. It is a teaching skill with sample
shaders, not a tested renderer, and it is about Earth-style skies seen from
the ground.

Take from it:

- Its cloud type profiles are merged into this skill as
  [cloud-types.md](cloud-types.md) (with how they carry over to gas giants)
  its full skill text as
  [ck42bb-procedural-clouds.md](ck42bb-procedural-clouds.md), and its shaders as
  [sources/ck42bb-procedural-clouds-shaders.md](../sources/ck42bb-procedural-clouds-shaders.md).
- Its performance notes agree with ours: bake 3D noise once (128^3 RGBA8
  is 8 MB), blue noise jitter on the start step, quarter-res or half-res
  march with a bilateral upsample, temporal reprojection marching a
  quarter of the pixels per frame.
- Lighting it covers (two-lobe Henyey-Greenstein, Beer-powder, silver
  lining, time-of-day palettes, radial-blur god rays) is the same set this
  skill already uses; nothing new there.
- Its fixed 80-step march with 6 light steps is a demo budget, not a
  guide for planet scales.
