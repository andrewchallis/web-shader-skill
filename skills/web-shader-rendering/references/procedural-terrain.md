# Procedural terrain on a globe, guided by a height map

Lessons from building close-up Earth ground (lifted patch mesh plus
procedural surface textures, three.js TSL on WebGPU and WebGL2) over 21
rounds of desktop stills. The source map was a 1.2 km per texel, 8-bit
bump-style height layer; the camera went down to about 15 km. Numbers are
examples from that work, not defaults.

## Height

- **The map is the guide; noise only adds what the map can't hold.** Pick
  the kind of noise from the map: ridged noise where the map is rough
  (local relief, `|height - blurred height|` over ~10 km), gentle swells on
  plains, nothing at sea. Height alone as the roughness made plateaus and
  high deserts crumple.
- **Hybrid ridged noise** (each octave weighted by the ridge above it) makes
  gullies run down ridges instead of across valleys.
- **One height function feeds both stages.** The vertex shader lifts the
  mesh with octaves the mesh can carry (fade by mesh cell: about 2.5 cells
  a wave); the fragment uses the same function for light and textures.
- **Read the guide with a B-spline** (four bilinear taps) until a texel is
  about one pixel. One bilinear tap lit each texel as a flat facet on far
  ridges; only near-camera B-spline left far snow blocky.
- **Baked noise beats live noise for terrain.** A 64^3 half-float Perlin
  texture (one read per octave, octaves turned against each other) halved
  the ground's cost against MaterialX noise and cut compile time.
- **Noise must live on the planet, not the mesh.** If the globe turns by
  sliding its map coordinate (static mesh, spinning uv), noise on the mesh
  position crawls across the land. Feed noise the direction of the spun
  map coordinate instead (wrap u with fract).
- **Patch skirts** hide cracks between LOD patches, but their screen-space
  normal is degenerate (the undisplaced position doesn't change down the
  skirt). Light them with the mesh normal.

## Lighting the relief

What worked: **the mesh's own normal for the big shapes, tilted by the
screen slope of only the detail finer than the mesh.**

- Vertex normal: finite differences of the lift function a cell either
  side, but only from octaves of about 6 cells a wave or longer. With
  2.5-cell octaves, each vertex's one-cell difference caught a different
  phase of the finest waves and grained the shading.
- Fragment detail: only octaves of about 20 pixels a wave or more, and
  fade them by the **long side of a slanted pixel** (footprint / cos of the
  view to the ground). Below that, skimming views alias into 2-pixel-tall
  flickering bars. 2.5, 6 and 12 pixels all stepped or grained on bright
  snow; green slopes hid it.
- Watch the area clamp in the screen-slope normal
  (`g * max(|det|, eps) - grad`): with `eps = 1e-10` in planet radii it
  silently flattened all relief closer than about 60 m a pixel. That
  "smooth" look hid the aliasing until the clamp was fixed.
- Lighting from the screen slope of the **whole** height drew thin dark
  dashes along straight lines near the camera. Taking the big shapes from
  the mesh normal removed them.
- A smoothstep inside each texel of a baked noise texture (to hide
  trilinear creases) puts flat spots at every texel and hatches the
  surface in fine diagonal stripes. Plain trilinear looked better once only
  well-sampled octaves were lit per pixel.
- WGSL `dpdx` (what three's `dFdx` emits) may run coarse, one value per
  2x2 quad. `dpdxFine` is available through a tiny custom node; here it
  wasn't the cause of the stepping, the footprint was.

## Surface, haze and water

- Surface textures (rock bands by height, forest clumps, dry ripples, snow
  off steep faces) from the map's colour, faded in by pixel size. Take the
  slope for rock and snow from the mesh normal, not screen derivatives:
  coarse derivatives speckled it in 2x2 blocks.
- Close up, haze by the air the view actually crosses, and greyer near the
  camera; add a little blue skylight in terrain shadow. Otherwise shaded
  valleys read as water.
- A soft water mask makes the sea's glint shine on land near coasts. Gate
  glint to open sea (`smoothstep(0.6, 0.95, water)`).

## Sea close up

Lessons from 13 more rounds on the same globe, camera from about 60 km
down to 5 km over open sea.

- **Waves hand their slope to the glint's roughness.** A few octaves of the
  same baked, planet-fixed noise (600, 250, 100 and 40 m) tilt the normal
  while each spans a few pixels. As an octave shrinks below that, its slope
  variance moves into the GGX roughness instead (keep the total near a
  wind-roughened sea, about 0.04). So the glint breaks into glitter close
  up and stays one smooth patch far off, at the same overall size.
- **Use a long fade per octave** (`1 - smoothstep(0.15, 0.6, foot / l)`).
  A short one dropped octaves out in rings round the point below the
  camera.
- **Isotropic waves line up into arcs round the camera** once the sky's
  reflection is added: the reflection picks out the slope along each line
  of sight. Stretch the crests (read noise with one axis divided by 2) so
  the sea has a wind direction. Fading the rings harder did nothing; the
  arcs came from the waves being isotropic.
- **Make the waves move by layer, not as one sheet.** Drift each octave
  downwind at deep water's speed for its wavelength, `sqrt(g l / 2 pi)`
  (swell ~30 m/s, short chop ~8 m/s), so the pattern changes as it goes.
- **Sun sparkles** are the peaks of a fine noise (about 15 m) lit by a lobe
  wider than the sea's roughness. Lessons:
  - Multiply two fine fields drifting opposite ways, so each facet lives a
    moment and goes. One fixed field read as white dust.
  - Widen the lobe only a little (alpha x1.6) and cut its tail
    (`lobe * smoothstep(0.08, 0.4, lobe)`). A wide lobe spread them evenly
    over the whole sea, again like dust.
  - Fade them out below about a pixel and let them clip to white, so the
    app's bloom can star them.
- **Far waves turn to static.** Fade waves and sparkles off by distance from
  2 to 10 times the camera's height (no nearer than 10 to 50 km); past that
  the sea is a smooth sky mirror with the glint's roughness. A narrower band
  (3 to 7 times) left a visible line. Fading by the slanted pixel's
  footprint, which worked for terrain, blurred the near waves too.
- The sky's reflection belongs on all open sea; hide only the sun's glint
  under cloud. Cutting both by cloud cover left hard black blotches.
- Pale and bright sky near the horizon, deeper blue overhead, picked by the
  reflected ray's height, reads as water from high up.

## City lights at street level

- The global night map stays the truth for how bright a place is; street
  data only says where inside each ~1 km cell the light lies. Use the night
  map as a weight, `pow(r, 1.5)`: it saturates over dense regions.
- Streaming vector road tiles (OpenFreeMap, no key) at zooms 12, 10 and 8
  into **one** canvas atlas kept the Earth shader under WebGPU's 16-texture
  limit. Three separate maps came to 18. Fade each region near its edge so
  mip bleed between regions doesn't show.
- Light = roads times street density, plus a soft (~150 m) glow over
  built-up areas. Draw minor streets dashed, as lamps. Landuse fills drawn
  as light looked like painted blocks; overlapping place polygons
  (quarter, suburb) double-counted. Add lights after fog.
- Credit OpenStreetMap (ODbL) wherever the streamed lights ship.

## Cloud lit from below

- At night, light the cloud's underside from the city lights under it: a
  blurred mip of the light map, `pow(below, 1.5)` for the gentler curve.
  Check where the cloud shell is front-side only: then the glow is seen
  from above only, and a camera under the deck sees nothing.

## Ground fog

- Fog lies where the ground is below its own ~10 km average, in patches
  tens of km across, and hides by its thickness over the view's slant
  through it (`thick / max(mu, 0.08)`).
- Gate it by ground type from the map colour (green or snowy country; very
  little over deserts) or it fills canyons with cumulus.
- Wavy tops (two noise octaves on the fog depth) and soft patch edges;
  hard flat tops read as cloud decks or snowfields.
- A thin veil with wisps over high snow is subtle; judge it side by side.

## Tried and didn't work

Kept as a record so the next attempt doesn't repeat them. Each line is what
was tried, what it did, and what replaced it.

Ground relief and lighting:
- **Roughness from height alone** crumpled plateaus and high deserts like
  paper (Grand Canyon rim, Atacama) and lost the canyon. Replaced by local
  relief (`|height - blurred height|`).
- **Live MaterialX noise** for every octave: about 2x the ground's cost and
  a 12 s shader build. Replaced by a baked 64^3 Perlin texture (1.8 s).
- **One bilinear tap of the height guide** far out lit each 1.2 km texel as
  a flat facet. **B-spline near the camera only** left far snow blocky.
  Fixed by keeping the B-spline until a texel is about one pixel.
- **Noise on the mesh position** crawled across the land as the globe
  turned (the globe spins by sliding its map coordinate).
- **Screen-slope normal on patch skirts** drew thin dark dashes along
  ridges; skirts need the mesh normal.
- **Lighting from the screen slope of the whole height** drew thin dark
  dashes on near snow, along the baked noise's trilinear creases.
- **Smoothstep inside each noise texel** to hide those creases put a flat
  spot in every texel: fine diagonal hatching. Smoothing only texels larger
  than a pixel still added a texel-sized ripple. Plain trilinear won once
  only well-sampled octaves were lit per pixel.
- **Mesh normal from 2.5-cell octaves:** each vertex's one-cell difference
  caught a different phase of the finest waves and grained the shading.
  Needs octaves of about 6 cells a wave or more.
- **Per-pixel lit detail at 2.5, 6 and 12 pixels a wave** all stepped or
  grained on bright snow. Only 20 px a wave, faded by the slanted pixel's
  long side, was clean (and cheapest).
- **Fine derivatives (`dpdxFine`)** for the 2-pixel stepping on near snow
  changed nothing. The cause was the slanted footprint, not coarse
  derivatives.
- **The `1e-10` area clamp** in the screen-slope normal flattened all
  relief closer than ~60 m a pixel. It looked smooth but hid the aliasing;
  removing it exposed the real problem.
- **Rock and snow slope from screen derivatives:** 2x2 speckle. From the
  mesh normal with all octaves: clean but about 1 ms more at Everest, so
  only coarse octaves (10+ cells) and only near.
- **Wobbling only the 32K map coordinate** to hide the texel grid missed far
  snow, which came from the 8K map. Both maps need it.

Haze and fog:
- **The orbit view's haze close up** turned shaded valleys blue, like
  water. Replaced by haze by the air crossed, and skylight in shadows.
- **Valley fog with no ground-type gate** filled the Grand Canyon like
  cumulus. **Flat fog tops and hard patch edges** read as cloud decks or
  snowfields.
- **The lab's near plane at 5% of height** clipped the air shell at 178 km
  and drew a straight seam: a lab bug, not the shader. Fixing it moved a
  smaller haze jump to between 180 and 120 km, still open.

City lights (OSM, ten rounds over Milan):
- **NASA value as the brightness** close up: the whole Po valley glowed
  cream (the map saturates).
- **Fields away from roads getting the cell's light back:** brown blotches.
  **Town, industrial and rail land drawn as fills:** flat map polygons.
- **Light from the cell average along roads:** lone rural roads as bright as
  Milan. Brightness needs street density.
- **Too dim overall** read as a dim web; centres need a glow mass.
- **Glow from street density** lay over farmland in blotches. **A blurred
  built-up mask** smeared off towns; overlapping district outlines doubled
  it. **A sharp built-up mask** drew crisp polygons as bright as the roads.
  Kept: ~150 m soft mask, scaled by density, under the roads.
- **Lights under the valley fog** vanished in skim views; they add after
  fog, softened.
- **Three separate light maps** pushed the Earth shader to 18 textures,
  over WebGPU's 16. One atlas fixed it.
- **The first cloud glow from below** was too faint to read, and the NASA
  map's coarse blur under cloud was a flat wash. Stills from 15 km showed
  no glow at all: the camera was under a front-side-only cloud shell.

Sea:
- **Cloud cover cutting the sky reflection** as well as the glint: hard
  black blotches on open sea.
- **A short per-octave fade:** waves dropped out in rings straight down.
- **Fading harder against the rings round the camera** had no effect. The
  cause was isotropic waves; stretched crests fixed it. A per-octave axis
  shuffle was tried as a suspect and wasn't needed.
- **Sparkles as one fixed fine field:** evenly scattered white specks, like
  dust. **8 m facets at x6:** one faint pixel at 5 km, lost against the
  glint. **A lobe of 0.3, then 2.2x roughness at x24:** sparkles spread over
  the whole sea, lit far from the sun, still dust.
- **Fading far waves by the slanted footprint** (as for terrain) removed the
  far static but blurred the near waves; a gentler slant fade still did.
- **A distance fade from 3 to 7 times the height** (15 to 35 km minimum)
  left a visible line where the waves ended. 2 to 10 times (10 to 50 km)
  hid it.

Test setup:
- A lab "Alps by day" view was at night, and at 5 km the camera sat inside
  the mountains, which tore the frame. Check sun side and ground height
  before reading a still as a bug.
- A loading check waited for the app to pause, but that stop auto-plays:
  it looked like a hang on main too.

## Ground and clouds together, and zooming down to them

From putting the lifted ground under Earth's close clouds and letting the
viewer zoom down to 12 km (Nov 2026, lab, desktop RTX 4070, WebGPU).

- **Light the lifted ground by the sphere's normal, not `normalWorld`.**
  With the ground patches lifted from the globe's shader, some longitudes
  drew their day side as night: black ground and lit street lights under
  sunlit clouds. Taking the normal from the object-space position
  (`modelWorldMatrix * vec4(normalize(positionGeometry), 0)`) and the view
  cosine from `cameraPosition - positionWorld` fixed it. All six check
  stills (sea skim, Alps skim, Pacific with the sun at 60 degrees, at 20 km)
  were daylit afterwards. We didn't pin down why `normalWorld` was wrong on
  the patch mesh. On any lifted or re-meshed surface, don't trust the
  geometry's normals for day and night; use the sphere's normal.
- **Split a combined-layer bug with the same view in two subjects.** Draw
  the ground-only lab subject and the full Earth subject (clouds and ground)
  with the same layers, views and sun in one run. Matching results put the
  fault in the ground shader, not in how the layers combine. Include a
  view over open sea, not only land: one bad longitude can hide on land.
Zoom and tilt below are the design as written, checked only in a unit
simulation so far, not yet in motion on the desktop:

- **Zoom in log steps of height, not of distance from the centre.** Near a
  globe, steps in centre distance barely move at 20 km. Steps in height
  above the surface move as far at 20 km as at 2,000 km.
- **Tilt towards the horizon low down.** Below about 200 km the view tilts
  from straight down to about 0.1 radians below level at the floor
  (12 km, clear of the highest lifted ground), in log steps of height.
  Straight down at 20 km shows a flat map; the horizon shows the clouds
  and air as layers.
- **Pull the near plane in with height**, as the app does close to Earth
  (about a quarter of the height, at most 1% of the distance), or the
  near ground and cloud get clipped. Set it the same way in the lab
  subject, or lab stills won't match the app.

## Workflow that saved time

- An A/B look per suspect in one page load (same views, several looks)
  isolated each artefact in one round: mesh-normal lighting, skirt tint,
  no-detail, plain vs smoothed noise.
- Measure grain as the mean difference from a 3x3 blur and relief as the
  spread after a 9 px blur on a fixed crop; it separates "busier" from
  "more relief".
- Check that lab place coordinates include the globe's axial tilt and its
  starting turn before trusting "this is Everest".
