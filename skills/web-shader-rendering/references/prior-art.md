
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
