
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

## CK42BB starfield, weather and landscape skills (MIT)

The same author as the clouds skill has three sibling skills, copied whole
into `sources/` (MIT). Same caveat: teaching samples for an Earth-ground
view, not tested at our scales.

- [procedural-stars-threejs](https://github.com/CK42BB/procedural-stars-threejs)
  (`4c04e03`) -> [sources/ck42bb-procedural-starfield.md](../sources/ck42bb-procedural-starfield.md).
  Most relevant to Elsewhere's skies and nebulae. Useful bits: uniform
  sphere placement with `acos(2r-1)` (linear sampling clusters at poles);
  blackbody colour per star (all-white stars look fake); point size from
  magnitude, twinkle in the vertex shader, one Points draw; Milky Way as
  FBM band with dust lanes subtracted and a brighter core; nebula types
  (emission, reflection, dark absorption, planetary) with a 48-step cap on
  the raymarched one and a pre-baked billboard as the cheap option; layer
  radii for parallax; explicit render order and additive blending without
  depth writes; a WGSL compute shader that builds a star catalogue.
- [procedural-weather-threejs](https://github.com/CK42BB/procedural-weather-threejs)
  (`26ad580`) -> [sources/ck42bb-procedural-weather.md](../sources/ck42bb-procedural-weather.md).
  Aurora curtains (vertex-displaced plane), dust storm and ground fog
  shaders, branching lightning, one shared wind field driving every
  effect, eased state transitions (no pops), camera-centred particle spawn
  box, GPU particle update in WGSL. Ideas for Jupiter lightning, aurora on
  the giants and Mars dust.
- [procedural-landscapes-threejs](https://github.com/CK42BB/procedural-landscapes-threejs)
  (`f7c147a`) -> [sources/ck42bb-procedural-landscapes.md](../sources/ck42bb-procedural-landscapes.md).
  Noise recipes (FBM, ridged multifractal, domain warp, terraces,
  combined multiplicatively), seed handling, WGSL compute heightmap,
  normals and hydraulic erosion, chunk seams fixed by sampling identical
  world-space noise. Relevant to Mars and Moon close terrain.

## gokayfem shader-skills (MIT, GLSL)

[shader-skills](https://github.com/gokayfem/shader-skills) (checked at
`a56e773`, Oct 2026, MIT) is an agent skill for Shadertoy-style GLSL: 186
functions in 20 modules (SDFs, noise, volume, atmosphere, colour, tonemap,
debug), a bundler, a checker and 11 example shaders including volumetric
cumulus. Every function is an original implementation of a published
technique, listed with its source in `CREDITS.md`, and checked on the GPU
(SDF bounds, noise derivatives against finite differences, curl noise for
zero divergence). Shadertoy GLSL, not TSL, so port what you use.

Take from it:

- **`volumeStep`**: the energy-conserving step (Hillaire): per step,
  `T_step = exp(-sigmaT * ds)`, add `T * (S - S * T_step) / sigmaT`, then
  `T *= T_step`. Stable in dense media at 30 to 60 steps where
  `radiance += T * S * ds` over-brightens and leaks light. Copied in
  [sources/gokayfem-volume.glsl](../sources/gokayfem-volume.glsl) with its
  phase functions and Beer-powder.
- **Phase in artist units**: multiply HG phase by 4 pi so isotropic is 1
  and the Sun term is on the same scale as the ambient colour; without it
  the ambient wins and clouds look flat.
- **One debug-mode numbering for every shader** (0 final, 1 distance
  field, 2 normals, 3 ids, 4 step count, 5 density or masks, 6 lighting
  terms split into R, G, B), and the rule to inspect the broken field
  directly rather than guess from the shaded frame. Worth copying as
  query flags in a lab harness.
- Also in its library: blackbody colour (Krystek fit), Sun limb darkening
  (Neckel 1996 constants), PCG hashes instead of sine hashes (which differ
  per GPU), interleaved gradient noise for jitter, AgX tone mapping.

## three-good-godrays (zlib, WebGL)

[three-good-godrays](https://github.com/Ameobea/three-good-godrays)
(checked at `2d15ba9`, Nov 2026, zlib-style licence keeping the credit to
N8python's original) is a screen-space god ray pass for Three.js on the
pmndrs `postprocessing` library, WebGL only.

Take from it:

- Rays are marched in screen space from each pixel towards the light,
  testing each sample against the light's **shadow map** to find lit air:
  real occlusion from scene geometry, not a radial blur of bright pixels.
  It needs shadow maps on, which a space scene usually doesn't have, so
  for a star behind a planet or ring the occluder test has to come from
  another source (an analytic sphere or ring intersection is cheaper).
- The march runs at reduced resolution, then a **bilateral blur** and a
  **joint bilateral upsample** against full-resolution depth put it back
  without halos at edges. The same two passes suit any half-resolution
  volume (clouds, haze) that has to sit cleanly against sharp geometry.

## PWhiddy Fat-Clouds (no licence, CUDA)

[Fat-Clouds](https://github.com/PWhiddy/Fat-Clouds) (2018) is a small 3D
fluid simulator and volumetric renderer in about 600 lines of CUDA.
**No licence file**: ideas only, don't copy code. Not usable in a browser
as is.

Take from it:

- The full stable-fluids loop on a 3D grid: advect velocity, density and
  temperature; add buoyancy from temperature minus ambient and weight from
  density; compute divergence; Jacobi pressure solve; subtract the
  pressure gradient. Each step is a compute kernel, so it maps onto WebGPU
  compute passes and 3D storage textures. Small dissipation per field
  (0.998 for density, 0.9999 for temperature) keeps it alive for long runs.
- Its renderer is the plain baseline: up to 512 steps per pixel with a
  light-occlusion march at every step. Fine for offline frames, far too
  costly live; bake the light or use a shadow volume.
- Use: a short simulated puff or plume (a stellar wind burst, a storm
  outflow) baked into a 3D texture and played back, rather than noise
  pretending to move like a fluid.

## shader-effects-inc shaders (MIT, WebGPU)

[shaders](https://github.com/shader-effects-inc/shaders) (checked at
`1f71d11`, Nov 2026, MIT for the engine, components and bindings; the
presets and editor at shaders.com have their own terms) is a library of
200+ 2D screen effects for websites (gradients, glass, blurs, lens and
light effects), written as WGSL through TypeGPU, not Three.js or TSL. Most
of it is web-design decoration; a few parts match camera effects.

Take from it:

- **Lens and light generators** as small pure functions: falloffs, lobes
  and bands behind SunBurst, Godrays, LensFlare (seven ghost layouts kept
  as a config table, not shader code) and a spectral lens (barrel or
  pincushion bulge plus a colour fan gathered over a runtime-count loop).
  See `packages/core/src/gpu/kit/lightfields.ts` and `lensParts.ts`; port
  the maths to TSL if a lens ghost, fringe or glare look needs rework.
- **One gather for all motion blurs**: linear, orbit and zoom blur are the
  same 32-tap Gaussian gather with only the tap path swapped
  (`motionBlur.ts`). Taps run in premultiplied colour.
- **A primitives catalog with a rule**: check the catalog
  (`gpu/kit/CATALOG.md`) before writing inline maths, and treat a
  hand-rolled copy as a review defect, so a fix made once reaches every
  shader. Pure float helpers also get CPU golden-value tests. Both habits
  suit any project with many similar shaders.
