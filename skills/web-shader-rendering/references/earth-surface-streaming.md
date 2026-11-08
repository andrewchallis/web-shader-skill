# Earth imagery, camera and terrain across scales

Read this alongside [Earth cloud transitions](earth-cloud-transitions.md)
when a globe must support close views. Start by tracing the existing
renderer, imagery loaders, terrain selector and camera callers. More
texture resolution, finer geometry and closer navigation are separate
changes: improving one does not automatically improve the others.

## Evidence and scope

These findings come from the 3dsolarsystem.online deployment inspected on
8 November 2026: [viewer](https://3dsolarsystem.online/viewer/#/earth),
[bundle](https://3dsolarsystem.online/assets/index-DYFMcyZp.js) and
[source map](https://3dsolarsystem.online/assets/index-DYFMcyZp.js.map).
Module paths below identify original sources inside the map's
`sourcesContent`. The hashed deployment may disappear; this is a dated
source inspection, not a promise about future builds or measured GPU
performance. Explain the architecture independently; its proprietary code
is not licensed for copying into this skill's MIT sources.

Normal inspection stops about 2 km above the displaced surface. Local
ground in rocketry is a separate mode, not worldwide street-level terrain.

## Imagery hierarchy and provenance

| Layer | Inspected data and use |
| --- | --- |
| Broad Earth view | NASA Blue Marble day map and supporting globe textures |
| Refined day imagery | NASA GIBS Landsat WELD annual composite, 1999, through level 11 (about 31 m/px at the equator) |
| Finest day level | Sentinel-2 cloudless 2016 from EOX, about 10 m source data, resampled into level 12 at roughly 15 m/px on the viewer's grid |
| Night imagery | NASA Black Marble 2016, about 500 m, with closer streets from OpenStreetMap via OpenFreeMap |
| Clouds | Separate coverage data and rendering; see the cloud reference |

Modules: `data/earthImagerySource.js`, `rocketry/earthimagery.js`,
`rocketry/earthdetail.js`, `rocketry/nightimagery.js`, `nightstreets.js`.
The viewer's credits identify the night datasets/providers; the inspected
module list establishes the separate night paths, not a full audit of
their vector-tile renderer.

A source pixel size differs from output tile spacing and from the detail
actually visible on screen. Do not call a resampled 15 m output grid
10 m geometry or street-level imagery. These mosaics also differ in date:
new districts or reservoirs can appear when 2016 detail replaces 1999.
Colour matching cannot make changed geography agree.

Preserve dataset attribution separately from the renderer's licence.
The inspected Sentinel composition uses the 2016 dataset credited as
CC BY 4.0; do not assume other years or providers have the same terms.

## Tile selection and bounded residency

The day streamer, `rocketry/planetimagery.js`, is a sparse virtual texture:
one bounded GPU atlas plus page tables that map geographic regions to
resident tiles. It is shared by Earth and other bodies.

- Earth tiles are 512 by 512 pixels on an equirectangular grid. Their
  angular span is 288 / 2^level degrees, with roots at level 3, a page-table
  level of 8 and refinement through level 12.
- Reject candidates beyond the horizon and outside the view frustum.
  Score remaining tiles by projected size, using distance to their
  geographic extent; a bounding sphere enclosing a low camera can
  otherwise demand far too much detail at grazing angles.
- Split the highest-demand parent into four children until the tile
  budget or maximum level is reached. Different split/retain thresholds
  (620 versus 420 projected pixels in this example) prevent repeated
  split/merge flicker.
- Missing fine pages resolve to resident ancestors. Keep a coarse globe
  fallback available too; do not expose blank squares during a download.
- Desktop's default day atlas is 8 by 8 slots; mobile uses 6 by 6 and caps
  selection at 20 leaves. The usual desktop selection budget is 48.
  Atlas capacity includes space beyond selected leaves: do not equate
  selection count with complete GPU residency.
- The streamer limits downloads to 10 in flight, with 2 low-priority
  child-prefetch jobs when ordinary loading is idle. Decoded images are
  discarded after upload; browser Cache Storage retains reusable tile
  responses. GPU residency and downloaded-byte caching are separate budgets.
- Tile transitions fade over 1.2 seconds, with a short grouping hold so
  neighbouring arrivals sharpen together. Version cache identities when
  the dataset or composition changes.

The normal site bundles Landsat levels 3–6; finer ordinary tiles stream
from NASA. Development/offline builds may include more. Patched imagery
has local copies and must not fall back to the unpatched remote bytes.
Failed requests should retain coarse coverage, and cancelled/stale work
must not replace a newly selected region.

## Match imagery before blending levels

Landsat and EOX use different tile grids, but both are plate carree.
The inspected composer gathers the EOX tiles overlapping a Landsat-grid
page and draws them with scale and offset, without a projection change.
Other providers may require reprojection; matching longitude/latitude
labels alone is not enough to establish grid compatibility.

A separate per-tile colour fit can draw visible squares because each tile
contains different proportions of sea, sand or city. This composer uses a
spatial gain/offset field based on overlapping neighbourhood statistics,
then smooths it. Neighbouring pages evaluate matching values at shared
edges. It excludes no-data and EOX's flat offshore fill, keeping the
Landsat parent where that fill contains no measured water detail.
Composed JPEGs are cached like ordinary imagery.
Module: `rocketry/earthdetail.js`.

The practical invariant is that adding a level sharpens a place without
recolouring each tile independently. Check shared edges, coastlines,
date-line wrapping and imagery-date changes, not just a central crop.

## Camera limits and precision

In `earthclose.js`, Earth radius is 6,371,000 m and inspection clearance
is 2,000 m. `main.js` enforces both a minimum orbit distance and a safety
push above the visual displaced surface. A centre-distance clamp alone
would still let mountains intersect the camera.

For Earth inspection, zoom speed decreases with altitude (clamped from
0.0015 to 1.2); rotation interpolates from 0.0004 to 0.8 over roughly
2–2,000 km altitude. The near plane also follows altitude, corresponding
to approximately 1–1,000 m before scene-scale conversion. These are example
tunings, not universal control or depth-buffer settings.

Within 1.2 Earth radii of the centre, the inspected camera offset and
target follow the surface's rotation. Otherwise accelerated simulation
time sweeps geography past a close camera and continually churns tiles.
Keep camera tracking, map addressing and the chosen simulation clock
consistent; do not compensate by freezing unrelated scene time.

The close pass transforms the camera through the complete inverse Earth
mesh transform, then converts to real metres. It draws camera-relative
geometry with the local camera at the origin, preserving small-scale
precision while the main scene retains its display scale. Include spin,
tilt, scale and orientation in this conversion. A near-plane reduction
cannot by itself repair large-coordinate float precision.

## Atmosphere and depth handover

The normal viewer blends the exterior atmosphere shell toward a local
sky dome across 3,000–8,000 km altitude: local sky dominates below that
band, exterior shell above it. This is independent of the cloud volume's
100–200 km handover.

The local pass reuses the globe's geometry and vertex displacement in
depth, and builds occluder proxies for foreground models. This keeps
mountains, spacecraft and satellites in front of the appropriate sky or
cloud contribution. Atmosphere haze must also agree between passes:
adding full ground haze over an already hazed globe doubles brightness.
Module: `earthclose.js`.

Do not solve a seam by hiding it with extra exposure or haze. Compare limb,
nadir, grazing terrain and an opaque foreground object through the entire
overlap, with matched lighting and tone mapping.

## Ground terrain is another layer

Rocketry's `terrain.js` uses four nested curved grids in a site's tangent
frame, with an outer fade into the scaled globe. It has aerial imagery
around Cape/Kennedy Space Center, broader fallback imagery and local
coastline-driven relief: water at sea level, low coastal plain, beach and
dunes. The ground-contact model uses the same terrain-height function.
This does not establish a detailed worldwide Earth DEM, buildings or
walkable geography.

Keep imagery LOD distinct from terrain LOD. A photograph on a smooth
sphere remains a smooth sphere. For actual ground entry, verify matching
height queries, geometry, surface collision and depth across the globe
and local mesh before reducing the camera clearance.

## Reuse check: universe-lab snapshot

The comparison in this investigation read local `origin/main`
[877ad0c8d91d3897df261574d2a94c47e8163bed](https://github.com/andrewchallis/universe-lab/tree/877ad0c8d91d3897df261574d2a94c47e8163bed)
(build 471); remote verification was unavailable then. This is an example
inventory, not a current project requirement.

- `earth-today.js` selects `hd` by default; `white-dwarf.js` enables
  streamed surface, night and cloud layers on non-low-memory devices.
- `earth-detail.js` keeps four nearby tiles per layer on a fixed 16 by 8
  grid, with KTX2 loading, coarse fallback, fades, stale-load checks and
  sliced GPU uploads. Its 32K global imagery is about 1.2 km/px at the
  equator, not a multilevel pyramid reaching tens of metres.
- `terrain-lod.js` already supplies adaptive geometry, horizon rejection,
  capacity limits, hysteresis and skirts. Its inspected callers were
  Mars and future Earth, not today's Earth.
- `solar-explore.js` sets Earth's nearest orbit to 1.4 radii, about
  2,548 km altitude. Flight pacing and near clipping already respond to
  surface clearance.
- Optional `earth=patches` shading reuses photo detail but explicitly
  loses geographic accuracy below about 5 km. Apparent detail does not
  establish higher-resolution measurements.

The smallest next change should extend the existing missing layer, rather
than rebuilding streaming or terrain infrastructure. Recheck current
callers and asset provenance before using any of these historical facts.

## Acceptance checks

- Record descent and ascent with nadir and grazing views; test both
  imagery and atmosphere overlaps, camera tracking and mountain clearance.
- Delay/fail tile requests and revisit regions; check parent coverage,
  cancellation, cache-version changes, shared borders and the date line.
- Separate measured geographic detail from synthetic shading; inspect
  changed-date features and offshore/no-data fallbacks.
- Exercise the low-memory path and both supported rendering backends.
  Measure GPU memory, request pressure and motion on target hardware.
- Treat source inspection, numerical checks and native visual/performance
  validation as separate evidence. This reference supplies only the first.
