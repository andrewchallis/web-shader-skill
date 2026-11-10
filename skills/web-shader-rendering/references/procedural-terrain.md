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

## Ground fog

- Fog lies where the ground is below its own ~10 km average, in patches
  tens of km across, and hides by its thickness over the view's slant
  through it (`thick / max(mu, 0.08)`).
- Gate it by ground type from the map colour (green or snowy country; very
  little over deserts) or it fills canyons with cumulus.
- Wavy tops (two noise octaves on the fog depth) and soft patch edges;
  hard flat tops read as cloud decks or snowfields.
- A thin veil with wisps over high snow is subtle; judge it side by side.

## Workflow that saved time

- An A/B look per suspect in one page load (same views, several looks)
  isolated each artefact in one round: mesh-normal lighting, skirt tint,
  no-detail, plain vs smoothed noise.
- Measure grain as the mean difference from a 3x3 blur and relief as the
  spread after a 9 px blur on a fixed crop; it separates "busier" from
  "more relief".
- Check that lab place coordinates include the globe's axial tilt and its
  starting turn before trusting "this is Everest".
