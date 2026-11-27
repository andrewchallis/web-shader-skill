# Frame cost and stalls: what worked, what didn't, what's next

Lessons from about two weeks of performance work on a large Three.js
WebGPU app (r186, TSL node materials, one continuous scene with planets,
gas and post effects), measured on an RTX 4070 desktop at 1920x1080 and an
M4 Mac. Numbers are examples from that app, not targets. "Pause" means a
frame that took far longer than its neighbours; "cost" means GPU or CPU ms
in a steady frame.

Two things kept turning out true:

- **The slow part was rarely where we first looked.** Three of the biggest
  wins (31 MB of buffer uploads a frame, a canvas read back from the GPU,
  9,600 rocks placed in JS) were not shaders at all. Profile the frame
  (CPU profile, buffer upload trace, GPU timer) before changing a shader.
- **Fewer pipelines or smaller shaders don't always mean faster frames.**
  Measure the thing a viewer sees: frame time, the longest pause, the
  number of frames over 50 ms.

## Worked

### Steady frame cost

- **Cache a far background and turn it between redraws.** A sky drawn
  behind a planet every frame (the whole far scene into a render target)
  cost 1.5-4.5 ms. Draw it at most every 60th frame, or at once when the
  camera's turn would show an edge that was never drawn (more than about
  3 px), or when its settings change. In between, reproject the last
  picture to the new view with a homography (K R K^-1, zoom included).
  Treat brightness as a separate gain (current level / drawn level; redraw
  if it drifts more than 5%), not a reason to redraw. Skip drawing it while
  it can't show (faded out, or one body covers all four frame corners).
  GPU ms off/on: gas giant 4.2 -> 2.1, Sun 3.3 -> 0.7, Earth 3.2 -> 2.8
  (Earth gained least; we didn't find out why). Open
  costs of the trick: a stale camera effect baked into the picture, and
  time-driven sky motion frozen between draws.
- **Cull big patch meshes by view, but measure.** Drawing only the ground
  patches inside the view saved 5.4 ms (4.7-7.6 by spot) on a costly
  close-up terrain, with frames unchanged. The patch bounding boxes
  reach 1 km below sea level, so lifted or sunk patches aren't culled
  while still in view.
- **Swap a second draw for its maths.** A cloud deck drawn twice (two
  blended layers) gave a look people liked. Drawing it once with coverage
  `a * (2 - a)` gives the same look for one draw: about 10 ms a frame
  saved in a close dive.
- **CPU-bound frames: look at per-object JS.** A scene stuck at 60-65 fps
  with a 9.5 ms GPU frame was placing about 18,600 small objects in JS
  every frame (10-12 ms). A scalar loop with the orbit rate cached, same
  results bit for bit, took it from 64 to 93 fps. Tools: a V8 CPU profile
  of the frame (Chrome traces of a few seconds run to gigabytes), and frame
  phase timing split into update, draw and submit.

### Buffer uploads

- **`DynamicDrawUsage` re-sends the whole attribute on every render.**
  three's WebGPU backend uploads any attribute marked
  `DynamicDrawUsage` in full each time it is drawn, changed or not
  (`Attributes.update`: `data.version < attribute.version || usage ===
  DynamicDrawUsage`). A streamed terrain with four 6-9 MB patch attributes
  sent about 31 MB a frame while gliding (11-16 GB in 12 s, 1.5-1.9 s of
  `writeBuffer`). Keep the default usage, and when a patch slot changes,
  mark only that slot with `addUpdateRange(start, count)` and set
  `needsUpdate`. Add a test that reads three's source for that line, so an
  upgrade that changes the rule is noticed.
- **Don't compact a big index buffer when one slot changes.** Packing
  visible slots to the front re-uploads every slot after the first change
  (up to a 20 MB index list, about 1 GB per glide). Zero culled slots in
  place instead (degenerate triangles) and upload only those ranges.
- To find these, wrap `GPUQueue.prototype.writeBuffer` in a probe page
  and log bytes and ms by buffer size and by caller. Buffer sizes are
  usually enough to name the attribute.

### Readbacks and page work

- **Never read a canvas back every frame.** A city-lights map checked its
  5120 x 3584 canvas with `getImageData` on each new tile. The probe canvas
  was made with `willReadFrequently`, which keeps it on the CPU, so each
  read cost 53-78 ms. Using a GPU canvas and checking at most every 2 s took
  frames over 50 ms in a 12 s glide from about 40 to 3-4.
- **Layout reads: moving them doesn't help if the page changes between
  paints.** `getBoundingClientRect` in a per-frame label pass cost about
  0.5 s per 12 s glide. Reading all rects once at frame start moved the
  cost but didn't cut it (-6%, within noise): whatever first reads layout
  after the DOM changes pays for the layout. Fix the writes (fewer DOM
  changes per frame), or cache rects and refresh them on resize, not every
  frame.

### Shader builds and load pauses

- **Make shaders smaller with loops and lookup tables.** A terrain
  fragment shader of 467k characters became 347k (and 577k -> 461k) by
  writing octaves, texture layers, slope taps and 8 Sun steps as TSL
  `Loop`s, with per-octave values in `array()` tables (index with
  `float(x).toInt()`) and an early `Break` once an octave's weight is 0.
  Build time dropped by about a third and the longest load pause by 36%.
  Textures read inside a loop can't use a layout function (see
  [webgpu-webgl2.md](webgpu-webgl2.md)), and nested loops need their own
  index names. The picture was similar, not identical (fine speckle in
  forest and shaded slopes): show a labelled before/after and let the
  owner judge.
- **Read a costly noise once.** Worley (cell) noise called four times for
  the same point was read once into a `.toVar()`: 4 -> 2 calls in two
  star shaders, pixels identical, lab compile 19% faster. It didn't
  shorten the app's pause, because that pause came from another shader
  (see below); still worth doing.
- **Warm up the real draw.** A cold warm-up draw only queues a shader's
  build, and the pipeline is asked for on a later draw, so drawing once
  hidden built nothing. Passes that need the camera (half-size cloud,
  history buffers, baked wisps) must be warmed with a real camera, and
  repeated until nothing is left to build. Building them once the camera
  is within some distance (20 planet radii) took a dive from 1.26 s, 543
  and 246 ms freezes to no frame over 100 ms.
- **Warm what a later draw will need, wherever the camera is.** Two big
  ground shaders made only when relief first switched on built in one frame
  (a 4.6 s stall). Drawing them in the hidden warm-up took the longest
  freeze to 1.1 s and moved the rest to 0.5 s pauses earlier, where the
  camera is still.
- **Build in pieces, with frames in between.** Splitting a shader build
  into its stages (setup, analyze, generate, per shader stage) and letting
  a frame draw when more than about 12 ms of pieces have run since the last
  frame cut the total pause time by about 30%. It did not cut the longest
  pause: three's fragment setup stage expands the whole node graph in one
  recursive call and can't yield inside. Only a smaller graph shortens it.
  This copies private three code, so pin a test to three's source.
- **Put hidden helper cameras on their own layer.** A rays pass with its
  effect off still had a fresh camera at the origin on layer 0, and its
  render target redrew after each resize, so it drew the whole scene once
  more and built about 21 large volume materials in one frame (765 ms in
  a software run; a freeze on arrival on the desktop). Give helper cameras their
  own layer from creation, and show hidden objects during warm-up draws so
  they build then.

## Tried and didn't work

- **Always 4x MSAA** to halve pipeline variants: 61 fewer pipelines, but a
  galaxy scene went 85 -> 67 fps with no visible gain. Dropped.
- **Culling a gas giant's globe deck in blocks** (1.54M triangles): up to
  0.09 ms saved, 0.4-0.7 ms slower at three close views. The vertex work
  was never the cost; the fragment shader was. It was kept on, but expect
  nothing from culling a mesh whose fragments are the cost.
- **A WGSL cell noise loop with uniform bounds** (so the driver's compiler
  can't unroll it): compile time within scatter, GPU +0.1 ms, pause
  unchanged. Dropped.
- **Leaving scenes out of the background warm-up** when a page opens at a
  later stop: about 20 fewer pipelines after Play, the same 0.9 s pause,
  and seeking back took 3 s longer. Dropped.
- **Shrinking shaders with layout functions alone, for speed:** cloud
  shaders 6.94M -> 6.05M characters, same pipelines, no measurable speed
  change. Size helps the build pause only when the shader you shrink is
  the one that blocks.
- **Holding the street map's re-uploads** (a test flag): frames over 50 ms
  3-4 -> 0-2. The whole-map upload was a small part; the readback was the
  cause. Dropped.
- **Reversed depth** (`reversedDepthBuffer`): only fixes depth precision,
  not float32 vertex jitter near a planet in a galaxy-sized scene. It
  needed several fixes to keep pixels the same (far clamps must clamp from
  below, `Vector3.project` z flips, warm-up must compile with the FloatType
  depth target or pipelines build twice). Left behind a flag.

## Why a still camera can be a loading bug

On a freshly opened page, a background warm-up of other scenes was still
running when Play was pressed. Two steps landed a few seconds later: a
hidden draw of a heavy scene (one 1-1.6 s frame) and a 190 MB map preload.
The app held its clock while three's `DefaultLoadingManager` was busy, so
the camera stood still for over a second and then jumped (100-150 ms
frames just under the "stall" line still advanced the clock by the whole
frame). Lessons:

- Give background preloads their own `LoadingManager`, so they don't look
  like the visible scene loading.
- A camera recorder that opens each stop as a fresh page records the
  warm-up, not the path. Wait for the warm-up's "done" mark before Play.
- A clock that skips long frames but advances by every frame under the
  line turns many medium frames into visible jumps. Capping the step is
  an idea, not tried.

## Measuring

- **Label every timing CLEAN or NOT CLEAN.** Other GPU users moved numbers
  more than the change: the desktop compositor (dwm) added about 20% while
  someone used the screen, a game editor in the background took about
  67% of the GPU, and the lock screen capped frames at 57 Hz. A NOT CLEAN
  run can still name a cause (a trace, CPU self time); don't use its frame
  times.
- **A/B/A/B in one turn**, one page load per variant, same stop, same
  camera pose. Check the A-to-A spread first: twice it was larger (2-2.6
  ms) than A-vs-B, so the run proved nothing either way.
- Toggling a runtime flag after load and letting it settle saves loads,
  but a paused app may not redraw after a toggle. For stills, use one
  fresh load per variant with a URL flag.
- Time the shot that matters. A benchmark that parks the camera at a
  height never reached the close cloud; only the real camera path did.
- GPU timestamp readouts in three r186 give the newest resolved frame,
  not a sum; when frame time is far above GPU time, the CPU or the page
  is the limit.
- Software renderers (SwiftShader) are fine for finding which shaders build
  and when, and for error checks, not for timing or looks. Some shaders
  never build there (too few sampled textures).

## What might be next

These are open leads from that app, in rough order of expected gain.
None is measured yet.

- The same `DynamicDrawUsage` pattern on other streamed meshes (a second
  terrain and a future-Earth surface): likely the same whole-buffer upload.
- The index list re-pack on cull (zero in place) once the attribute fix is
  timed.
- The remaining big fragment shader (about 124 atlas reads for city
  lights in one pass): fewer reads, or a pre-baked lower level far off.
- Building the biggest shaders asynchronously from the start, so the one
  setup stage that can't yield happens before the viewer needs it.
- A separate `LoadingManager` for background preloads, and the camera
  recorder waiting for warm-up.
- Number formatting in a per-frame label pass (`toLocaleString`, about
  0.15-0.2 s per 12 s glide): cache an `Intl.NumberFormat`.
- Transparent double-sided materials build two pipelines each, and passes
  without MRT build again. Cutting either changes how things draw.
