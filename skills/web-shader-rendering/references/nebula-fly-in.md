# Flying into a nebula

Lessons from 16 desktop rounds in the lab and about 20 more in the app on one ray-marched emission nebula that the
camera flies into, from five cloud radii out to a resting point near the
centre. The target was a filmic, documentary look. The base shader is a
spiral-noise density march of the Duke / Helix Nebula family (a distance-like
field `|neb|`, an adaptive step, glow from stars inside, re-emission,
an S-curve finish), on Three.js TSL, WebGPU first.

Each section says what worked, then what we tried that didn't.

## Detail all the way in: nested levels

One baked field can't hold detail from five radii out to a hundredth of a
radius. Nests can: smaller copies of the field (each with its own bake),
centred on the resting point, each fading in inside its own bound.

What worked:

- **Blend the nests into one field.** At each step, weight each nest by
  `fade_k * (1 - fade_{k+1})` (the weights sum to 1) and blend the raw
  field values, then run the density, step and lighting once on the
  blended value. A nest's threads then run straight into its parent's.
- **Gas per length rises slowly inside.** With a blended scale `Rf` (cloud
  radii per nest unit), multiply the gas per step by `Rf^-thicken` with
  thicken about 0.25. At 0 the inner nests were too thin to see; at 1
  each nest was as thick as the whole cloud and read as a separate dark
  object.
- **Glow and darkening follow the length stepped.** Scale per-step glow,
  re-emission and the "always darken" term by the step length as a share
  of a full outer-cloud step. Fixed per-step amounts multiply with the
  number of steps and the cloud brightens as you go in.
- **No step crosses into a nest.** Outside a nest's bound, clamp the step
  to the distance to that bound, or rays skip a nest.
- **Coarser features near the resting camera.** Running a nest's noise at
  1.4-2.4 times its own unit size makes nearby gas bigger on screen than
  far gas, which reads as depth instead of a flat fractal.
- **Depth near the resting point.** Features a cloud radius away barely
  change over the last stretch of a fly-in, so the shot looks frozen. It
  needs gas and dark voids near the camera, not more far detail.
- **Fill the inside.** The outer shape's distance field went so negative
  inside that the whole middle was empty and the nests floated in a dark
  hole. Clamp how far inside the shape keeps thinning (a `fill` limit).

What didn't:

- **A second, finer cloud marched in its own units.** It read as a
  separate object every time: its own colour, filaments about 40 times
  finer, sitting in a cleared void.
- **Each nest accumulated at its own step.** Gas per length scaled as 1/R,
  so each nest drew as a dark ball inside the last.
- **Separate nests seen "from outside".** A pocket cleared round each nest
  so you see its surface: read as objects inside objects, not one cloud.

## Bakes: what to bake, what to keep live

Cost history on a desktop RTX: the unbaked first version spent 19 of its
22 ms at the resting point on the inner cloud alone; the first bakes ran
18-48 ms; baking plus one noise read per step (instead of one per nest)
brought it to 8-14 ms, and the final look runs at about 6-11 ms.

- Bake each nest's low octaves into a half-float `RedFormat` 3D texture
  (128-160 per side), once, in time slices so the page never stalls.
- **Keep the finest octaves live.** Octaves finer than about 6 texels per
  wavelength run in the march, continuing the same noise (the same
  rotation and frequency it would have had after the baked octaves). The
  split is exact: check it in JS against the full-octave function.
  Without it, gaps between gas sheets showed round "bites" (texel corners).
- **Ease each texel** (smoothstep the fractional texel position before
  the trilinear read): plain trilinear left scalloped edges on dark gaps.
- **A shared bake is never cancelled.** Two clouds (a lab swapping looks)
  shared one cached bake; when the first was disposed it cancelled the
  bake and the second sampled its 1x1 stand-ins: every nest read as solid
  gas (dark balls, featureless haze, 50 ms frames).

What didn't:

- **Low-passing the bake** (fading octaves finer than N texels per
  wavelength out of the bake, no live octaves): it removed the thin
  sheets that carry the cloud, so a mid-distance view went black.

## Brightness that doesn't climb as you go in

A ray through the middle of a cloud crosses more gas than a ray from
outside, so the view doubled in brightness from 1.5 to 0.6 radii and the
viewer read it as "too bright for a nebula".

- **Exposure by camera distance from the centre:** a small table of
  `[radius, gain]`, log-interpolated. Tune it so the gas's median frame
  brightness stays about level (we held 30-45 of 255) through the
  fly-in. Measure the median, not the mean: a bright star skews the mean.
- **Halo light along every ray** (the star glow added whether or not gas is
  there) laid a flat pale wash over the whole view; cut it to about 0.3.
- **Keep the hue when clipping:** scale an over-bright colour down as a
  whole instead of clipping each channel, or bright blue gas turns cyan
  and every colour region reads teal.

## Colour

"Throw some colour in" and "don't aim to match the old one" moved it from a
single blue to an emission-nebula mix.

- Two broad, slow noise fields fixed in space (not per nest) swing the
  light colours from the base palette toward magenta and teal, as ionised
  gas does. Continuous through every nest because they're in cloud space.
- Shrink the regions with depth (`x / Rn^deep`, deep about 1), or the
  whole inside is one hue.
- Teal on top of magenta needs a later threshold (teal only where its
  field is high) or teal wins everywhere.

## Smoke the camera flies through

"Whiffs of smoke the camera flies through" took three attempts.

What worked: **puffs as extra gas in the march itself.** Lay a dozen
puff centres along the approach path; each frame upload only the three
nearest to the camera (testing all of them every step doubled the cost).
Inside a puff, swap the density for sheets cut from the live fine noise
(`|fine - level| * sharp`) so they read as loose wisps.

What didn't:

- **Camera-facing sprites** read as flat cards, or not at all.
- **Letting the puff's density set the step.** A puff around the camera
  made every step tiny and the ray ran out of steps: the frame went black.
  Step on the cloud's own density; the puff only changes what's drawn.
- **A fixed start offset** for the march (or one by camera distance) drew
  radial streaks inside puffs. A random fraction of the first step per
  pixel (interleaved gradient noise) fixed them.

## Stars inside: twinkle and glare

- Glare spikes from a shared spike function on a camera-facing card that
  keeps one size on screen (card = distance x a constant), with the
  star's core kept its world size by passing the core's share of the card.
- Twinkle: a product of slow sines gave a gentle "breathing" swell. It
  reads as twinkling only when a quicker flicker leads: about 8 Hz and
  10-15% of the brightness, over a small swell. A 5% flicker on a 30%
  swell still read as breathing, and a perfectly regular flicker can read
  as a pulse, so vary its rate per star. A near-white core shows it less.
  Judge it in a still-camera clip at 60 fps: a fly-in hides it, and 12 fps
  aliases the flicker into a slow swell. Leave the gas lighting steady;
  only the sprite twinkles.
- Draw the sprites with zero alpha (colour added, alpha untouched), so
  they don't count as gas in any opacity mask or motion-blur weight.

## God rays from a star behind the cloud

Asked for: "one star further behind the nebula so ... light rays coming
through and being broken by the nebula." Five rounds.

What worked: **screen-space light scattering cut by the gas pass's
opacity** (the classic radial blur toward the star's screen position,
summing a soft disc of its light less whatever the gas covers):

- Draw the cloud alone over a clear (alpha 0) half-float target, so its
  alpha is the gas opacity. An opaque scene backdrop sets alpha to 1.
- **Scale the opacity up before it cuts the rays** (we used x10). Thin
  emission gas has low alpha everywhere and let nearly all the light
  through: a soft glow, no lanes.
- **Let the rays light the gas, don't add a layer.** Add
  `gas.rgb * rays * boost` plus only a faint `rays * haze`. Added as their
  own grey layer, rays lit the faint outer gas into grey blotches and
  drew spokes into empty space.
- **No glow round the star where there's no gas.** The usual "near the
  light" glow drew a grey disc over every hole in the gas.
- **Fade them out deep inside**, where the star is buried behind most of
  the cloud; they're at their best from outside (one or more radii out).
- Cost on a desktop RTX: about 0.1 ms (a half-resolution 48-step blur
  over the gas pass the frame draws anyway). An early reading of 1.5-4 ms
  was the profiler, not the rays (see process notes).

What didn't:

- **Volumetric shafts in the march.** We baked the light reaching each
  point from the star through the gas (a 64-96^3 transmittance grid, a
  second of JS) and scattered it forward (Henyey-Greenstein, g 0.7-0.85)
  in the march. With thin sheets as occluders the shadows average out
  along each ray: it rendered as a white fog patch, no beams, and too
  bright close in. A wide gas window (whole clumps cast shadows) gave
  rays only from far outside. The grid is still useful to dim the
  star's sprite by the gas in front of it.
- **Mirrored rays.** When the gas pass is a render target you drew
  yourself and sample with screen UV, the star's screen position needs y
  flipped (`0.5 - 0.5 * ndc.y`) on both WebGPU and WebGL. Check that the
  rays radiate from the star's sprite before tuning anything else.

## Moving it into the app

The lab look then went into a documentary-style shot: the camera flies past
a star, turns and travels into the cloud. These lessons came from that move.

What worked:

- **Steady rays.** In motion the rays flickered. Two causes: the source
  star twinkled, and the coarse gas cut shifted a little each frame. Hold
  the source star steady (no twinkle; the other stars can keep theirs) and
  blend each frame's rays over the last few (we kept 15% new per frame).
  Restart the blend in full on a cut, a seek, a long frame gap, a camera
  jump or a fast turn, or the beams trail behind the star.
- **Two fixed texture nodes for that history.** Two targets drawn in turn,
  each reading the other through its own texture node. One node swapped
  between the targets kept its first binding on WebGPU, so a target read
  itself, which the GPU rejects: no beams at all. Read both with screen UV;
  `uv()` flipped one of them on WebGL.
- **A floor on the source star's glare** (about 0.12 of full), so the rays
  never seem to come from an empty corner when the gas hides the star.
  At 0.35 it read as a separate star.
- **Rays from a quarter-size view.** Drawing the cloud alone at quarter
  size for the ray pass looked the same as half size and cost about a
  third (1.5 against 4.3 ms on a desktop RTX).
- **Bigger cloud, same stars.** When asked to double the cloud keeping its
  stars the same size, scale the cloud and pass the star cores a separate
  scale, so they move apart without growing.
- **Fog that builds near the resting point.** Dense, same-colour fog round
  the centre that thickens as the camera gets close gives the last stretch
  depth. Keep it very faint outside. It cost about 2 ms.
- **Dim the background starfield on the way in** (we used half) and bring
  it back once inside, or a bright starfield competes with the cloud.
- **Ease the cloud in only once the camera has passed it.** The flight in
  went by the cloud early, and at full strength it flashed as a pale,
  hard-edged blob for 0.3 s. Easing it in while it sat behind the view
  fixed that.
- **Keep it drawn at a tiny strength (1e-4), not zero.** Hidden at zero,
  its shaders and passes were first built mid-shot: a 1.5 s freeze. At a
  tiny strength they build under the loading screen as before.

What didn't:

- **The full look on WebGL2.** On ANGLE over Direct3D, the nested march
  never finished compiling (the page was still loading after 10 minutes).
  WebGL got a much simpler procedural cloud instead. Time the WebGL2
  compile in the lab before the app swap, and plan a lighter build per
  backend from the start.
- **Endpoint stills to judge the hand-overs.** The flash, the freeze and a
  cut to another view on the way out only showed in motion: play the shot
  through each hand-over, forward and seeking back.
- **Stills taken just after loading.** The first still caught the loading
  screen's drawing still fading over the cloud. Wait a few seconds after
  loading ends before the first still.

## Process notes

- A cloud software renderer (SwiftShader) is fine for "is it on the star,
  is it grey", but desktop GPU frames decided every look call.
- Before/after columns (with vs without the new effect) on one contact
  sheet, two side views, six distances, plus a fly-in MP4 per round. One
  page load per look with the camera moved between stills made a round
  about five minutes.
- Measure the gas's mean and median brightness per still to track the
  "brighter as you go in" problem in numbers.
- When one variant draws its own passes and the other goes through a
  profiler's per-object split, their GPU times aren't comparable: time
  both the same way, each page loaded twice, interleaved.
- Hold the old asset out of the comparison once the brief changes from
  "replace" to "make it good": anchoring on the old look cost rounds.
