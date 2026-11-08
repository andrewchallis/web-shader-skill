
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

## Orbit to ground on a globe: 3dsolarsystem.online

[3dsolarsystem.online](https://3dsolarsystem.online/viewer/#/earth)
(Polyxmedia), plain Three.js WebGL, lets you zoom on Earth from orbit to
street level. Closed source; read from its shipped bundle in a browser
(cloud proxies block the site). Ideas only.

How it works:

- **Imagery as a sparse virtual texture** on the globe: 512 px tiles, a
  page table plus an atlas, levels 3 to 12 (about 15 m/px), cached with
  the Cache API. Street maps drawn from vector tiles into three nested
  textures round the camera.
- **A separate local scene near the ground**, in metres, on an
  east/up/north basis at a patch centre, with its own camera (a floating
  origin, so float32 holds). Nested ring grids with geomorph bands are
  rebuilt in 5 ms time-sliced jobs when the patch recentres, plus a
  horizon mesh. The globe shader cuts out the cap under the patch, and the
  local scene draws after a depth clear.
- Heights are procedural noise plus coarse bathymetry and a few hand-made
  sites, not a real elevation model (its Moon does use a DEM).

Lesson: going from orbit to ground needs a change of frame (local metres
and camera), streamed imagery, and a ground mesh that hands over from the
globe without a seam. The globe alone can't do it at float32.
