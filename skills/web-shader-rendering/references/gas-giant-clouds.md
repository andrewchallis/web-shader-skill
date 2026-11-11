# Gas giant clouds: the Jupiter record

Everything we tried for Jupiter's clouds from orbit down to a 400 km skim
(5 to 11 Nov 2026, about 200 rounds across five approaches), what worked,
what didn't and what is still open. Read it before doing cloud work on
Saturn, the ice giants, or any cloud that has to hold up from a whole-planet
view down to flying over it.

Code for the key pieces (chart, strip bake, swap fade, B-spline read,
bisected crossing, thin volume, storm, octave fade) is in
[gas-giant-snippets.md](gas-giant-snippets.md).

Numbers are from Jupiter (R = 71,492 km), a desktop RTX 4070 on WebGPU at
1440x900, and Three.js r186-r187 node materials. Treat them as examples.

## The arc in one table

| Dates | Approach | Rounds | Outcome |
| --- | --- | --- | --- |
| 5-6 Nov | Baked thunderhead SDF towers (the dust-pillar method) in a volume shell, plus a multiply overlay on the globe | about 24 | Pebbles from afar, cotton balls close up. Replaced. |
| 6-7 Nov | Saturn's close renderer (a 2.5D height field with carve noise) ported to Jupiter, then puffs, flow lines, carved banks, alpha shells | about 35 | Specks, wood grain, popcorn on a dark floor, pebbles with slice stripes. "90s video game." |
| 7 Nov | Continuous deck: map height, sinking lanes, Perlin-Worley billows, a "far surface" with no march | about 25 | Approved at 5,000 and 1,500 km "for now". Hairy tufts at the skim. Still today's look. |
| 8 Nov | Storm towers in the deck (Nightscape ideas) | about 45 | Better, but ringed stems, stepped shelves and a black lab sky along the way. |
| 9-11 Nov | Port of WeebLabs Nightscape: true 3D SDF heaps baked in windows on a planet chart, a far 2.5D relief shader, a 2.5D storm | 16 app + 56 lab | The best close look by far. Merged behind a lab switch; not yet on for visitors. |

The jump in quality came from changing approach (rule 8 in SKILL.md), not
from tuning. Close in, forty rounds of knobs on the height field never got
past "pebbles", "popcorn" or hairy tufts. The first faithful port of a real
3D cloud renderer got past them in a day.

## What worked

### Shape

- **True 3D signed-distance heaps beat any height field close in.** Each
  heap is a cluster of rounded "thermal bubbles" joined by smooth max,
  with billow noise added to the distance, as Nightscape does. Overhangs,
  stacked turrets and round bumps read as cloud. A height field can only
  make mesas, pits and columns.
- **Skewed height spread.** Mostly low and middling heaps with the odd tall
  turret, from a "vigour" noise much wider than one heap. Even spreads or
  one-heap-wide vigour fields read as a flat field.
- **A low deck between heaps with gentle relief.** A flat sheet between
  heaps reads as one uniform colour.
- **The map still leads.** Coverage and colour come from the planet map, so
  belts and zones stay where the globe shows them at every height. The
  heaps take the map's colour on their tops, a deep tint low down, and
  the highest tops pale a little.

### Near and far

- **3D march only where it can show.** The march draws below about
  1,000 km over the deck, and on a skim only within a few thousand km
  along each ray. Past that a much cheaper far shader carries the same
  cloud. The camera hides the switch (it looks at the horizon while the
  near heaps come in, then tilts down onto them).
- **The far shader is a short height-field march over baked top maps**,
  not a flat decal. From the bake, keep one texel per column with top
  height, optical depth and light. Then:
  - A short march down the ray finds where it meets that field, so heaps
    stand up, hide what is behind them and cast shadows.
  - Along grazing rays, flatten the field toward a reference height so the
    steps stay short.
  - Fade the relief to the plain map as the camera climbs (by footprint
    and by camera height), so it ends on today's globe look.
- **Far clumps need a thin volume, not a lit surface.** An opaque surface
  lit like ground read as rocks every time (rounds 32-42), however we
  rounded, domed or lobed it. What fixed it: after the coarse march hits
  the first clump, take 12 samples over a short span from half a step
  before the hit, gathering soft density and light, then let the deck
  show through by what is left. Starting the fine samples from the hit
  (which moves smoothly pixel to pixel) needs no jitter. A grid start drew
  ribs, and a hash jitter drew speckle.
- **Clumps as slabs over a separate deck.** Each clump is a lens from its
  top down a set depth, thinning to its edges, over a flat deck lower
  down. This gives steep sides that slide against the deck in motion and
  cast shadows onto it. Clumps that drop to the deck as part of one height
  field read as "physically connected" mesas.
- **Steep walls need a proper crossing.** On steep walls (a storm's eye
  wall) the coarse march draws horizontal stair-step ribs. A signed
  distance for the whole slab only softened them. Bisecting the last
  coarse step five times, then interpolating linearly, removed them for
  free.

### Light

- **Lift the gaps with multiple scattering and sky light, not with floor
  light.** Deep shaded cloud between near heaps went near black (about 25
  luma against 130 for the far band), a hard join on the dive.
  Brightening the floor, its shadows or the haze did nothing. What worked
  at no measured cost: two wider light paths through the cloud (a
  multiple-scattering share of 1.3 and 0.9), sky light up from 1.4 to 3,
  and a higher sky-light floor in shade.
- **Strong shading can turn into dark masses.** Heavier Sun shadow and
  occlusion judged on the old cloud drew dark masses with bright rims on
  real heaps. More light through the cloud and a brighter Sun kept the
  modelling.
- **Light far cloud as at its edge.** Far off, the edge ramp spreads over
  many units of depth, so most of what shows lies deep inside, where the
  light is nearly gone. That drew dark blotches from 2,000 km up. Take
  light and occlusion as at the edge the ramp stands for.
- **Floor shadows need a sky-light minimum.** Full-depth shadows on the
  deep floor drew near-black blotches from 2,000 km up.
- **Light the far tops like the march lights its tops**, with the same
  colour pipeline, so the hand-over keeps one colour. Toward the
  terminator, tone the far tops down, or they go grey-white.
  - The cause: on flat far cloud `dot(N, L) / L.y` is about 1 whatever the
    Sun's height, and a `sunUp` gate is fully open above a mu0 of about
    0.08. Neither carries the Sun's own fall-off.
  - Multiplying by it (mu0) took the dive's night-side cloud from 53 to 24
    luma, against 19 for the old look.
- **Light far tops from about one layer under the top.** Light within a
  layer of the top is near zero, so tops lit there drew white (174 against
  the march's 138). Lit as a plain diffuse surface they drew 184. Use the
  march's phase lobes and powder through that depth, and cap the top's
  optical depth so wide flat decks (a storm's arms) don't go brown.
- **A thin-volume glow sells far clumps as cloud.** Inner glow 3.5, Sun
  gain 1.5 and powder 0.8 gave light inside, bright warm tops and soft
  gradation for about 1.2 ms. Cool grey-white clumps read as ash; warm
  them to the planet's colour.

### Baking on a planet

- **Bake in windows on a planet-fixed chart.** Nightscape is a flat tiled
  world; a planet isn't. We used a gnomonic chart around the camera's path
  (axes fixed on the planet, 14 km a unit) with nested windows of 4 levels
  of size. Each level fades into the next coarser one over its window's
  outer fifth (a tenth showed a seam).
- **Bake in strips, a few a frame, taking turns between levels.** Baking
  all levels at once on the dive drew 87 ms GPU frames and a 576 ms hitch.
  But one strip a frame took 8-10 s on the dive, so the first bake and
  "urgent" re-bakes (the camera has left the window far behind) go at 8
  strips a turn.
- **Snap windows to the texel grid,** or the overlap re-bakes a fraction of
  a texel off and near heap rims shift at each swap.
- **Fade a window swap in over about 0.5 s.** Otherwise ground the old
  window didn't hold changes from the wide level's low smear to tall heaps
  in one frame.
- **Read wide levels with a cubic B-spline** (four filtered taps), not one
  filtered tap. Plain bilinear creases at every texel, and from 2,000 km
  up those creases read as horizontal hatching.
- **Keep today's cloud drawn until the first bakes finish,** then fade the
  new cloud in over about 1 s. A seek never lands on a blank.
- **Start the first bakes far out.** Started at 8,800 km they finished on
  the skim, after the whole dive, and the dive had no new cloud. Starting
  at 45,000 km fixed it.
- **Keep the old window up during a re-bake.** A "done" flag that stayed
  true mid re-bake left the close level showing a window anchored 25,000 km
  away, with no heaps at 440 km.
- **Store signed distances offset.** A bake target that clamps negatives
  read 0 everywhere and the whole view turned to fog. Store `(sd + 10) / 16`
  as Nightscape does.
- **A frame that runs ahead of its bake draws "fur".** Fur showed seven
  times, every time on a run sharing the GPU. Don't judge a look from a
  loaded run, and guard far shading against a lagging bake.

### Storms

- **A 2.5D storm is a domain warp of the clump pattern,** not a new shape.
  It has these parts:
  - The clump pattern is swirled by an angle that falls off with distance
    from the centre.
  - Log-spiral arms raise the clump signal, with clear lanes between them.
  - A ring of taller cloud stands round a partly clear eye.
  - A gentle swirl (2.5 radians at the centre) and a big storm (radius
    about 2,000 km) read best. A strong swirl combed the clumps into
    smears.
- **Make the eye wall asymmetric and low.** A steep ring round a clear hole
  read as a crater. A steeper inner side, a long outer slope, a low wall
  and a partly cleared eye read as cloud.
- **Fix the storm to the planet from the start.** Placing it "ahead of the
  camera" when the camera passed 3,000 km re-swirled 2,000 km of cloud in
  one frame: a pop everyone saw. A planet-fixed direction, set when the
  chart anchors, lets it fade in with the cloud.
- **Skip the swirl maths outside the storm's radius.** Run for every far
  pixel, it cost 1.8 ms with the storm off-screen. Culled, it cost 0.6-0.9
  ms.
- **Frame the whole vortex, eye included.** A spot picked on the chart
  without the shot in mind was never in frame.
- **Light the storm softly.** The 2.5D march lighting dimmed the arms; soft
  surface lighting inside the storm only brought the cream arms back.

### Haze and horizon

- **Keep near cloud clear.** Haze by full ray length washed out every view
  from 2,000 km up. Use a clear zone of 1,500 km from the camera, then
  haze, with extra gain toward the horizon.
- **Fade the limb band's top.** The skim's horizon haze had a hard top edge
  until it faded over a height range above the deck.
- **Rays that reach the deep floor still take its colour,** hazed by
  distance, past the march's far limit. Otherwise a black band appears
  past the far limit.
- **Haze the rays that slip through gaps.** Rays that pass through gaps in
  the near march and miss the floor took no haze. That drew a stair-stepped
  band edge with gold sky showing through holes, found with a limb debug
  view and the weights view. Give missed rays the sky colour, and haze both
  sides of every hand-over.
- **Match the haze colour to the sky.** A cool mauve haze against a warm
  gold sky showed as a line; `hazeRGB [0.95, 0.66, 0.3]` matched.
  - A horizon gain of 1.6 softened the edge, but the line stays while the
    sky is brighter than the haze at grazing angles.
  - Light the haze about one haze depth along the ray, not at the chord's
    middle.
- **Limit haze to below a set height over the deck** (about 400 km over the
  deck base here). Haze over the whole ray length veiled the belts
  grey-violet.

### Wisps (a cirrus veil)

- **Draw wisps only near the camera.** Far off they drew rings, rails,
  "vinyl-groove" stripes, grain and "fur in the distance". Drawing them
  only within 500-1,200 km of the camera removed the far problems and cut
  4 ms off the skim.
- **A low warp at large size** (600 km) gave soft combed cirrus. A high
  warp gave marbled "oil" whorls.
- **Fade them close to the camera too.** Bright streaks over near clumps
  survived near fades at 250 and 400 km and fewer octaves. Turning wisps
  off proved they were the cause, after five rounds of tuning; a near fade
  at 1,000 km fixed it.

### Near and far: what didn't move the join

- **Lighting the far band darker or with more contrast** didn't close the
  join. Removing the far band's pale tint cancelled the dimming.
- **Pushing the near reach out** (1,400-2,400 km along the ray from 900-1,600
  km) moved the join up and away and softened it to a band in motion. The
  costs:
  - a darker frame;
  - glassy streaks where the far slab fades over near cloud;
  - more dot speckle on the climb;
  - +1.6-3 ms.
- **Measure the join:** mean luma on each side, and the share of pixels
  under 20. The dive's join started at about 110 against 40, with half the
  near pixels under 20. After the light changes it was still about 2:1.
  Design both layers to agree on tone, contrast and detail size from the
  start.

### Motion and pops

- **Check in motion, frame by frame.** Our pops were all one-frame swaps:
  a window swap, a texel-offset re-bake, the storm placement, a fine map
  level arriving. Stills miss them; full-speed viewing misses some too.
  What found them was stepping through 25 fps frames across the suspect
  second, plus an automatic scan that flags frames whose mean luma change
  is over 3x the median of the frames around them.
- **No per-frame randomness in shapes.** World-anchored samples, no hash
  jitter on shape (see Nightscape in [prior-art.md](prior-art.md)).

### Process

- **Play the real camera path in the lab.** The lab runs the app's own shot
  code, turned into the planet's frame, in real time from one page load,
  so bakes happen in motion as in the app. It also takes a camera-editor
  track. Lab-only framings misled us twice. One round fixed at a lab spot
  had no lit heap field. Another took "300 km" from a shot that was
  really about 1,900 km up.
- **Debug weights view.** Tinting each renderer a flat colour (red march,
  green far shader, blue old cloud) answered "which layer is drawing
  this?" in one frame, again and again.
- **One look per page load, all stills from it, and the same times for
  every look.** A reload per still turned a three-minute scout into an
  hour.
- **Plain labels burned into every sheet.** Variant codes like "Z4" meant
  nothing to the person judging.
- **Log bake state with every still** (done, chunks, where the chart
  anchored). A short settle left bakes unfinished, and four rounds gave
  false "no cloud" verdicts. Seek a warm-up pose first.
- **Turn a feature off before tuning it.** An A/B with one layer off found
  causes that rounds of knob changes missed.
- **Timing:**
  - Only an exclusive GPU gives valid numbers; shared runs gave 50-185 ms
    frames.
  - Light views read an idle floor of about 8 ms whatever they draw. Time
    them with the scene drawn 4 times a frame (8.17 ms became 2.69 ms a
    draw).
  - Frame pacing can change between sessions, so compare within one run.
  - The same look on a shared GPU spread about ±1.3 ms between runs.
- **Software rendering is for functional checks only.** A SwiftShader
  harness hid the WebGPU clear bug, and a script that fell back to it
  played the lab path at 0.06x speed. Pass the real browser to scripts
  explicitly.
- **Parse each look's settings back before running it.** Shell variable
  and alias clashes silently dropped settings twice (PowerShell names are
  case-insensitive, and `FL` is a built-in alias).
- **A per-pass GPU profiler broke the lab** (a stack overflow and a frozen
  picture). Keep a plain per-frame GPU trace for timing.

## What didn't work

| Tried | What it looked like | Why, as best we know |
| --- | --- | --- |
| Baked thunderhead SDF towers in a volume shell | Pebbles from 2,000-6,000 km; cotton balls close up | Small separate shapes with nothing joining them; tower cells too regular |
| Multiply-blended tops overlay on the globe | "90s video game" | No self-shadow or depth; a decal |
| Puffs and flow lines in a height field | Specks, bubbles; streaks as height drew vertical smears, as shade wood-grain contours | Height-field detail can't make round 3D shapes |
| Carved banks on a bare floor | Popcorn puffs on a dark floor below 3,000 km | No continuous deck; floor clamp read as holes |
| 16 alpha-blended texture shells | Pebbles, slice stripes, a dark dip at the hand-over | Slices show at grazing angles |
| 3D Worley erosion of a deck edge at small size | Fuzz, cotton wool | Octaves under a few pixels |
| Strong Sun shadow and occlusion on real heaps | Dark masses with bright rims | Too little light through the cloud |
| Far clumps as a lit opaque surface (tall, lobes, round, dome) | Rocks, mesas, pancakes, ice floes | A surface can't thin out or glow at its edges. Lobes and round also cost about 3 ms. |
| A fine pass spread over the whole ray | Regular dotted grain | Too few samples per clump |
| Fine pass on the coarse grid / with hash jitter | Ribs / speckle | Grid start aligns samples; jitter is per-pixel noise |
| Signed slab distance alone on steep walls | Softer ribs | Wall far steeper than one step; bisect instead |
| Placing the storm when the camera passes a height | The whole swirl appears in one frame | A wide domain warp changes every clump it touches |
| A high cloud layer as a thin puff volume | Fly-through plates, a beige veil, popcorn; +3-4 ms | Thin volume seen edge-on at speed |
| The same high layer as a sheet | Flat cream decals, +1-2 ms | A sheet has no depth; parked |
| Brightening the floor or its shadows to fix black gaps | No change | The black was deep shaded cloud, not floor |
| Fading the near billow octave by pixel size to stop climb speckle | Speckle became horizontal ribs | The billows were hiding the field's layered steps |
| A rib-free surface by "anti-slice" knobs (finer inside steps, soft step size) | Bright striped band at the horizon | Grazing rays draw each step as its own layer |
| Wisp strands squashed straight along latitude | Hard rings | Needs warp; strands seen edge-on need fading |
| Worley or billow relief in the far height field | "Fur": grey step-sliced spikes over the far band | Relief changing faster than the far march's steps; put billows in lighting only |
| One fine detail octave on the far layer | "Reptile skin", chain-link mottle, stipple at the horizon | Detail far below heap-lobe size; heap-lobe scale (frequency 0.12) fixed it |
| Analytic heaps instead of the bake | Harsh and flat, blobby satellite spheres; 25-37 ms | 4-5x the cost of baked reads, no better look |
| Lowering the heaps to clear a 300 km skim | Empty deck; heaps sank into it | Raise the camera instead (a 400 km skim was clean) |
| More fine samples in the thin volume (16, 18) | No better; +2 ms, and fur over the dive at a long span | The fix was where the samples start, not how many |

## Planet-scale traps

- **Flattening.** Jupiter's polar radius is 0.935 of the equator's. A skim
  "300 km over a sphere of the equator's radius" at 34 degrees south was
  about 1,900 km over the cloud deck. Measure height over the deck in the
  shader's own space, never by the app's km readout.
- **Which mesh is drawn.** The shot flew over another scene's copy of
  Jupiter with a different pole tilt (3.1 degrees about z, not x). The skim
  ended up 100 km over the deck, inside the cloud. Read the drawn
  transform; keep one named constant for it.
- **Float precision close to a huge object.** Pass the eye position from JS
  (double precision) relative to the object, or close views go flat.
- **A chart that anchors far out.** A storm at a fixed chart point anchored
  at 45,000 km never showed on the dive. Pick positions from the planet,
  not from wherever the chart happened to start.

## Still open (11 Nov 2026)

From the end-to-end review of the app on main (build 496):

- **The dive goes dark from 30,000 to 1,500 km** (6-10.5 s) in both the old
  and the new look, with 200-320 ms stalls in the same stretch. Cause not
  found yet. Lesson whatever the cause: after 50 rounds tuning 300-3,000 km,
  nobody had looked at the whole path end to end. Film the full path from
  space to the lowest point every few rounds.
- **Bake stalls on the Nightscape dive:** frame p95 135 ms at
  6,000-1,500 km. Start bakes earlier, during the globe approach.
- **The close globe is soft** at 5,000-74,000 km on the climb out.
- **Bright rainbow-fringed bars** inside a near tower when the camera
  passes close (21 s). Not diagnosed.
- **Fine dot speckle** over the near cloud on the climb at 460-1,000 km,
  spread by the longer near reach. Billow fade turned it into ribs.
- **A one-frame sharpen** of far clumps at 8.72 s, probably a finer map
  level swapping in.

## Carrying this to other giants and large clouds

1. Start from the 3D SDF heaps and the far 2.5D thin volume, not from a
   height field. Change the heap profiles and palette per planet (Saturn:
   lower, softer, paler; ice giants: thin haze over a deep deck).
2. Reuse the chart, windows, strips and swap fade unchanged. Size the
   chart unit so the tallest heaps sit in the window's height range.
3. Measure heights over the planet's own flattened deck from day one.
4. Put any domain warp (storms, vortices) at a planet-fixed spot, set
   before the cloud shows.
5. Keep gaps lit by scattering and sky light. Check the darkest gap in
   every round, not only the bright tops.
6. Play the real camera path in a lab, then film the whole path in the
   app, from space to the lowest point and back.
7. Budget: on the RTX 4070 the Nightscape skim ran about 11 ms GPU (the old
   cloud 16 ms), but the dive's bakes cost up to 290 ms stalls. Plan bakes
   before you plan looks.
