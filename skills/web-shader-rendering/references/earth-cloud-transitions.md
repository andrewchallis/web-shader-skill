# Earth clouds from orbit to inside the layer

Use this when a camera descends from a globe view toward cloud tops or into
the air. First inspect the project's existing cloud maps, shell, streaming,
weather clock and local rendering passes. Extend those where possible.
A close orbital shot may need only better map filtering and top shading;
a volume becomes useful when thickness, side views or entering clouds
matter.

## Inspected implementation and limits

Example: [3dsolarsystem.online Earth viewer](https://3dsolarsystem.online/viewer/#/earth).
Inspected on 8 November 2026 through its deployed
[bundle](https://3dsolarsystem.online/assets/index-DYFMcyZp.js) and
[source map](https://3dsolarsystem.online/assets/index-DYFMcyZp.js.map).
The source map contains original module text in `sourcesContent`; paths
below are names inside that map, not a public source repository.
Deployment links can disappear. These are source findings, not measured
performance or visual acceptance. The site's code is proprietary: explain
techniques independently; do not copy it into the skill's MIT sources.

Normal Earth inspection keeps approximately 2 km above the displaced
surface. The separate rocketry mode has ground rendering and some different
cloud transitions. The following altitude table describes the normal viewer.

| Height above Earth | Source behaviour |
| --- | --- |
| Above about 4,000 km | No new cloud imagery pages requested; resident pages can remain. The globe's base map and filtered cloud-top field supply the distant view. This is a streaming cutoff, not a hard visual switch. |
| About 200–4,000 km | Globe cloud shader with streamed 1 km cloud imagery and procedural top shading. Detail depends on pixel footprint, not fixed altitude bands. |
| 100–200 km | Smooth transition between globe clouds and the local volumetric pass, when Earth is focused and the quality tier supports volumes. |
| Below 100 km | Full volume weight when enabled; unresolved distant parts still use filtered coverage. Low quality keeps the globe representation in the normal viewer. |

Source anchors: `rocketry/cloudimagery.js` (`STREAM_ALTITUDE`),
`rocketry/volclouds.js` (`GLOBAL_VOLUME_FADE`, `volumeAmount`),
`earthclose.js` (`cloudWanted`, `uEarthVolumeBlend`).
Rocketry separately uses 2D decks on Low and an 80–100 km deck/volume
altitude band; do not apply that band to the normal viewer.

## One field, multiple representations

Keep geographic addressing, reference coverage, wind and time consistent
across the globe and local pass. The example shares a spherical weather
field; the globe and volumes read its continuously advancing clock.
Latitude-dependent drift moves the cloud-map address. Tiles are selected
for the ground beneath that drifted map, not blindly beneath its original
UVs. A tile arrival, a quality change or leaving and re-entering the close
pass must not generate a new cloud arrangement.

The dynamic weather target updates about once per second (more often
during reference startup), while the shared shader clock advances between
updates. Do not confuse weather-field update cadence with animation rate.
Modules: `earthweather.js`, `shaders/earthweather.js`, `earthclose.js`.

A camera-relative local pass uses Earth-fixed axes and metres. Transform
the camera through the globe's complete inverse transform, including spin,
tilt and display scale. Reuse surface displacement in its depth prepass,
and include foreground models as occluders so cloud and sky composition
do not paint over them.

## Cloud imagery and stable detail

The base cloud map is approximately 8K wide (about 4.9 km/texel at the
equator). Streamed pages come from the same NASA Blue Marble cloud
reference at about 1 km/texel. Coarse and fine coverage therefore agree;
page arrival refines the outline rather than changing the weather.
This is historical reference imagery with procedural evolution, not live
meteorological data.

The example uses a single-channel R8 atlas, parent fallback and fades.
Desktop selects up to 48 leaves into a 12-by-12 tile atlas; mobile selects
24 into a 7-by-7 atlas. Below 600 km it prefetches a view about 1.3 times
wider on each axis, narrowing that margin toward 1,500 km. These are memory
and motion budgets to calibrate, not required constants.
Modules: `data/cloudImagerySource.js`, `rocketry/cloudimagery.js`,
`rocketry/planetimagery.js`.

Under the imagery's texel, a fixed procedural field supplies cells at
roughly 3 km, 1 km and 330 m scales. Coverage determines the threshold on
that field. Screen derivatives estimate each pixel's footprint in metres:
bands smaller than roughly 1.5 pixels are omitted and emerge toward three
pixels. Unresolved variance widens the coverage edge rather than adding
speckle, preserving average coverage as detail disappears.

Take regional cloud type and brokenness from the stable coarse reference.
Let finer pages change coverage without reseeding cells or changing their
type. The field also drives apparent top height, Sun occlusion and ground
shadows; the orbital impression of relief need not require a full 3D march.
Module: `shaders/earthcloudtop.js` (`cloudTopField`,
`cloudTopSunOcclusion`), used by `shaders/earth.js`.

## Blend clouds without thinning or doubling

Match cloud position, lighting and optical coverage before blending.
Use the same cloud-shell intersection for map addressing; a fixed UV
offset gives the wrong parallax near the limb. The example globe uses a
2 km cloud shell for that intersection.

A simple pair of complementary opacity weights thins an otherwise
identical cloud halfway through an over-composite. If desired opacity is
A, volume weight is w, and foreground volume opacity is Av = A*w, choose
background opacity Af = (A - Av)/(1 - Av). Then combined opacity
Av + Af*(1 - Av) remains A. Handle the fully opaque endpoint explicitly.
This derivation assumes matching layers, foreground volume over background,
linear colour and consistent alpha conventions. It is not a general fix
for two unrelated densities or incompatible lighting.
Module: `shaders/earthcloudcolumn.js` (`earthCloudFallbackAlpha`).

Include aerial perspective consistently on both paths, so the close cloud
composite does not overwrite the blue limb. Keep cloud opacity handover
separate from the atmosphere's own shell-to-sky transition.

## Volumes and their cost

The close path raymarches a spherical cloud layer in metres. Shapes and
erosion live in Earth-fixed space with wind. The sample cumulus parameters
place cloud base around 1.4 km and march bounds around 1.15–3.6 km; these
are artistic/model parameters, not measured global cloud heights.

Its pipeline is:

1. Full-resolution scene-distance prepass.
2. Reduced-resolution cloud shadow and cloud radiance/transmittance march.
3. Temporal reprojection using representative cloud depth in the Earth-fixed
   frame, wind compensation, disocclusion rejection and variance clipping.
4. Depth-aware upsampling and composition, followed by a cloud-depth stamp
   for later transparent geometry.

The High tier starts at half width and half height (one quarter as many
rays): 128 primary steps, 8 light steps, 560,000-ray budget. Medium also
starts at half dimensions: 96 primary steps, 5 light steps, 380,000 rays.
Larger buffers increase the resolution divisor to stay within the budget;
these are configured caps, not measured work per pixel or frame-rate claims.
Modules: `rocketry/settings.js`, `rocketry/volclouds.js`,
`rocketry/cloudshaders.js`.

At orbital footprints, the volume converges toward filtered cloud columns.
The implementation centres jitter and retires temporal history as that
representation takes over, avoiding an otherwise crawling map. Close
clouds retain jitter and temporal supersampling. Reset history on camera
cuts; do not keep accumulating through disocclusions or a changed field.

## Checks before accepting a transition

- Freeze weather and record a slow descent and ascent through both handover
  edges, with nadir and grazing views. Check coverage, silhouette and
  brightness in linear colour; verify there is no doubled front or thin band.
- Hold the camera still, then drag, orbit and cross a longitude seam. Cells
  should stay attached to the weather rather than screen pixels.
- Delay or fail tile loads, then revisit an area. Coarse coverage must remain
  available; new pages should sharpen it without changing cell placement.
- Exercise the volume-off tier and quality switches. Distinguish normal
  viewer fallback from a separate flight mode's deck fallback.
- Check foreground objects, terrain intersections and transparent geometry.
  Inspect temporal ghosting after cuts and cloud motion.
- Measure cost on the target GPU with isolated timing. Source settings and
  still frames do not establish stable motion or performance.

## Close cumulus heaps and the march: what worked, what didn't

From a polish pass on Earth's close clouds (a port of Nightscape's baked
heap field and march, 13 rounds, Nov 2026). Camera at 20, 8 and 3 km,
looking down and skimming the horizon, desktop RTX 4070, WebGPU.

What worked:
- **Broader, lumpier heaps.** Towers read as single balls until the
  bubbles that build a heap blended more softly (smooth-max k about 0.8 of
  the bubble radius, up from 0.45), joined the deck more softly (about 2x
  the old blend), sat further apart (offset about 1.3 radii, up from 0.75)
  and had stronger lobes. They now read as merged cumulus heaps.
- **Deck a little lower** (0.4 km) so the down view from 8 km clears it
  instead of sitting in its top.
- **No view-aligned planes for a thin deck.** The march's camera-facing
  sample planes, which suit thick gas, cut a deck a few hundred metres thick
  into a blocky striped patch at 20 km and streaks at 3 km. Plain steps
  that grow with distance (`dt = t * 0.005 + 0.025` in deck units, 1,200
  steps max) draw neither, and cost less: lab GPU ms fell in every view
  (3 km skim 6.3 to 4.4 ms).
- **Billow octave faded sooner** (100 to 250 units) cut grain on the far
  deck.
- **Timing method.** Run main twice and the branch once on a quiet GPU in
  one turn. The two main runs set the noise (0.06 ms or less here), so a
  gap bigger than that is real.

What didn't work:
- **Bake changes for the patch and streaks.** A wider bake window, 512
  instead of 256 texels, 54 instead of 36 layers, and more steps changed
  nothing. Neither did smoothing inside each noise octave, which cost 55%
  more. When bake resolution doesn't move an artefact, it's the march.
- **No planes with the old, coarser plain step** (`t * 0.016 + 0.08`).
  The patch went, but contour bands appeared on every heap. Steps three
  times finer removed most of them.
- **Finer steps alone don't remove every band.** Faint contour rings stay
  on some heaps at 20 km skim, thin wisps and hole rims show a comb fringe,
  and fading the billow octave early makes the mid-distance deck look a
  little airbrushed. Untested next step: jitter the march start per pixel
  by part of a step (fixed in world space, not per frame) and check it in
  motion.
- **Faint streaks remain** where the deck breaks up over the sea, looking
  straight down from 3 km.
- **Tall vertical streaks at 3 km, one suspect per look.** At 3 km over
  thick cover, skimming and looking down, five looks didn't bring the tall
  streaks back in the lab: today's march, the old camera-facing planes,
  no swell zones, lower towers and a taller bake. The old planes drew
  grain and contour rings at the rims of holes in the deck, and today's
  plain steps didn't, which fits the planes finding above. Lab stills at
  these views don't show the tall streaks, so look for them in motion in
  the app next.
