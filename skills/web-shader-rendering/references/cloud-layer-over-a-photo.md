# A marched cloud layer over a photo-mapped planet

Use this when a planet is a photo on a globe from far away and the camera
goes down into generated cloud: a thick layer marched for every pixel (as
flight sims do it), wound into storms, and handed over from the photo
without a seam. It is the record of 31 lab rounds on Jupiter on 12 Nov
2026, after the roughly 200 in [gas-giant-clouds.md](gas-giant-clouds.md).
Numbers are Jupiter's (radius 71,492 km, a layer 420 km deep, billows
420 km across); scale them to your subject.

Where a section says what failed, the failure cost at least one round.

## The layer

One shell a few hundred km deep. Density at a point is how much cloud the
photo says is there (its pale zones fuller, its dark belts thinner) times
a height profile times a Perlin-Worley shape, with finer octaves that only
wear the edges. Beer-Lambert per step, four to six growing steps toward
the Sun, two softer light paths for multiple scattering.

- **Bake the shape sum.** Five noise reads per density sample (two Worley
  sizes, Perlin lumps) baked into one tiling 3D texture (96 texels a side,
  8 big cells): each sample reads it once. With the Sun steps that is 2 to
  3 reads where there were 7.
- **Half size.** The layer drawn at half the screen's width and height and
  composited: GPU time at a low skim fell from about 10 ms to 2.6 ms, the
  picture within a slight softening. Do this before tuning anything else.
- **Height variety needs three things.** A broad cloud-type field (low
  sheets to tall heaps, a few thousand km across), the photo's cover, and
  scattered towers. Then narrow each billow upward (subtract a term that
  grows with height from the shape) so tops are domes. Without the
  narrowing, towers stood as flat-topped blocks.
- **Steps crowd toward the camera** (position = span x i^1.7), where
  detail is biggest.

## Close-range detail

The layer was soft below about 1,000 km. Three wrong guesses first: adding
finer octaves alone changed almost nothing; drawing at full size changed
nothing; four times the steps changed nothing.

**Detail smaller than the depth light passes through is fog.** The cloud
took 35 km to go opaque, so an 8 km dent in a cloud's face changed nothing
visible. What worked, all keyed to the size of a pixel at the sample (0.4
to 2.5 km), so the far look is untouched:

- near cloud up to 8 times as opaque, and its edge firmed (a smoothstep on
  the density);
- two close octaves that push the face in and out by the same amount
  (noise minus its mean), so they shape the cloud without thinning it;
- the fine octaves' pockets take less sunlight and their bumps more, since
  the Sun steps read the shape without them and they had no shading of
  their own;
- **short steps on a hit.** Walk the usual long steps on the cheap shape
  (no fine octaves: it is never less than the full density, so it can't
  miss cloud). Where one finds cloud near enough to matter, go back over
  that step in 5 short ones with the full detail, and stay short while
  still in cloud. Firm, opaque cloud under long jittered steps drew as
  grain; this is what removed it.

Give the short steps a **budget** (48 extra a pixel) after which the ray
carries on in long ones. Without it, rays inside the layer ran out of
iterations and left holes.

Failed: firming the edge after the octaves had cut (ate whole clouds);
skipping an octave not yet in view by multiplying it by zero (still read:
wrap it in an `If`).

## The floor is cloud too

Under the heaps the deck was the photo on a smooth sphere: from 500 km a
flat plain with a soft shadow on it. Make the bottom of the same volume a
full sheet of cloud, a few tens of km deep, rolling with the billows'
shape, so it has relief, takes the heaps' shadows and gets the close
detail.

- Lit like the heaps, the sheet filled the dark gaps of a low-Sun skim
  with pale cloud and the heaps lost their contrast. Light it by the Sun's
  height over it, as a surface would be.
- At full strength its self-shadow speckled under long far steps (a sample
  just under the top lit, the next black). Count it for a fraction (0.15
  to 0.4) in the Sun steps.
- The edge octaves stippled it from far off; don't wear it with them.
- For shape: regional depth from the cloud-type field, deeper under pale
  zones, humps of its own a third of a billow across. Firm crests read as
  dunes; a soft top (fading over 70% of its depth), thinner cloud and
  rounded crests read as cloud.
- **Openings must go through.** Hollows with a cloud floor 50 to 100 km
  down did not read as cavities at all from 1,500 km up, even with darker
  floors. Real holes onto a dark depth did. Cut them with the baked shape
  read several times coarser, its rim wobbled by the fine shape: a
  one-octave noise texture thresholded for the holes drew their rims as
  straight creases (its texels, magnified).

## Storms: carry the cloud along a flow

"Stormy" asked of round cells. What didn't work:

- **Warping the coordinates** with sine swirls on all three axes leaned
  every cloud over: combed, smeared streaks like motion blur.
- A **sideways-only warp** (east-west by latitude, as the jets shear) drew
  zigzags and chevrons. A warp moves each point once by a fixed pattern,
  so it draws that pattern.

What worked:

- **Trace back along a wind.** For each sample, take a few short steps
  (four) back along a flow and read the cloud field where it came from.
  The flow is the surface normal crossed with the gradient of a sum of
  sine waves: sideways everywhere, no sources or sinks, and a function of
  direction from the planet's centre only, so it is the same at every
  height and clouds stand upright. No texture reads. One trace serves a
  sample and all its Sun steps.
- **Leave the fine octaves where they are.** Read through the flow too,
  they were drawn out with the big shapes into smooth smears. Read at the
  sample's own place, a swept cloud keeps a billowed edge.
- **A vortex is a rotation that falls off.** Turn the traced point about
  the vortex's centre by an angle of twist x exp(-(distance/radius)^2)
  (Rodrigues' formula). Rows of heaps become spiral arms. Twist of 5 to 9
  radians wound the cloud into dozens of thin rings, like tree rings; 2.6
  is under half a turn and reads as a storm. Skip vortices a sample is
  outside with an `If` on the dot product.
- **Carry the colour too.** The cloud takes its colour from the photo. Read
  at the sample's own place, colour stayed put while shapes were wound:
  the straight edge of a pale region in the photo, magnified twenty times,
  lay across a spiral as a wedge with straight sides. Read the photo where
  the flow brought the cloud from. (This looked like a renderer fault and
  was chased as one: see "Process".)

### A storm you can fly into

Inside a vortex, rebuild the cloud floor as a bowl: a wall a couple of
hundred km high sloping inward to an open eye and outward into the
surrounding cloud.

- An even wall is a ring doughnut. Let its height follow the billows'
  shape, which the twist has wound, so it stands in spiral ridges.
- A ridge with a cliff outside it is still a doughnut. Make the top level
  from half the radius to the rim and slope gently into the surrounding
  cloud beyond: a wound plateau with the eye sunk in it.
- Carry a low floor of the same wound cloud across the eye, darker toward
  the middle, with only a small pit open. An eye open to the flat photo is
  a hole with a picture at the bottom.

## Handing over from the photo

Rule 2 of the skill, the far look is the map, with what it took here.

- **Put the generated feature on a real one.** Find a small storm in the
  photo, place the generated vortex at its latitude, longitude and size,
  and aim the descent there. Calibrate by looking: shoot the globe from
  high up across longitudes until the feature is centred. A worked-out
  position was a degree and a half off.
- **The seam was tone, not shape.** With a dark, heavy storm look the
  photo's pale oval became near-black openings between 8,000 and 5,000 km.
  Keeping the photo's tones (more light spread inside cloud, more sky
  light, shade on the floor never below 0.6 of its sunlight, openings and
  cloud bases left the photo's colour) made the same frames follow on.
- **The photo was taken under a high Sun.** Match its tones where the Sun
  is high over the cloud and ease back to full contrast as the Sun gets
  low, where shadows are long anyway. Otherwise a low-Sun skim goes flat
  and bright to suit a hand-over it never shows.
- **What isn't in the photo comes in by distance.** The photo's storm had
  a pale middle, so the generated dark eye came from nowhere. Its darkness
  is a quarter strength while a pixel there is 8 km or more and full by
  2.5 km: it deepens as the camera comes down. The same goes for carrying
  colour along the flow: full only close to, so through the hand-over the
  generated colours lie where the photo's are.
- **Cloud is whitened with height; a tall storm wall goes grey.** Don't
  whiten the floor sheet (or anything standing in for a region of the
  photo) with height.
- **Check the hand-over on the fastest, most oblique path you have.** The
  take-over (a pixel goes to the generated cloud once its cells are a few
  pixels across, every remaining pixel in a last short fade) looked smooth
  on a slow straight-down descent. On a dive falling 4,000 km a second at
  an angle it fell inside one or two frames: +15 of 255 in a quarter
  second. Starting the every-pixel fade far higher fixed it.
- **A sharper globe held late leaves a dark band on the horizon.** Toward
  the horizon the photo globe is darker than the close cloud that replaces
  it. Holding the globe until the cloud is resolved, to keep the photo
  sharp, left a dark band from 9,000 to 6,700 km in the app that the lab
  stills had not shown. Sharpness and the band are tied: fix by matching
  the two at the horizon, or hand the far pixels over earlier and accept
  the softness.

## Camera paths for judging a storm

- **Holding the view on the subject reads as flying straight at it**,
  whatever the path over the ground. For an approach from an angle, come
  down short of the subject and to one side looking where you are going,
  run in low with it off-centre on the horizon, then bank round it.
- On the run-in, look a fixed angle to the path's side of the subject
  (13 degrees with a 40 degree lens) so it holds a third of the way in
  from the frame's edge instead of sliding out as the camera closes.
- A level pass straight over a storm's wall at close range fills the lens
  with one white wall. Circle it outside the wall and above its crest.
- Ease a dive's height at the bottom only. Eased at both ends it is
  fastest in the middle, which is where the hand-over is.

## Measuring a fly-in

- Shoot frames at even steps of the path from **one page load with the
  clock held**, join them at the path's real pace, and say plainly that
  the result shows timing but not frame rate. About 0.65 s a frame here.
- Record mean brightness per frame and report the **largest change per
  part of the path** (planet filling the frame, hand-over, run-in, on
  station, leaving). One number for the whole clip hides where it is, and
  a lit planet filling a black frame is a big step that isn't a fault.
- Scout with a dozen stills (under a minute) before any long run. Three
  scouts found a skim flown into the storm's wall, a subject out of frame,
  and a pitch convention measured from the visible horizon, not the level.

## Process

Each of these was done wrong at least once in these rounds.

- **Test a cause before naming it.** Three confident wrong calls in a row:
  a pale wedge blamed on where short steps begin (it was the photo's own
  colour edge: it survived six toggles); a "colour seam" that measured as
  none (the storm matched the photo to a point of RGB; the surroundings had
  left the frame); a brightness mismatch that measured within 4%. Toggle
  one thing at a time until the fault goes, and measure patches before
  saying a colour or brightness differs.
- **Check which settings a run used.** A filter the owner expected was
  never switched on across ten rounds, because each run's settings were
  copied from the last.
- **The lab can't clear a look for the app.** The dark horizon band only
  showed in the full app with its own camera and Sun.
- **Brief a reviewer by time, not by coverage.** Two builds, two renderers
  and five scene groups ran over an hour for a change a visitor sees in
  fifteen minutes. Give an order of priority and a cap.
- **Count evidence as you go.** 31 rounds of labelled sheets came to
  24.7 MB against a 3 MB limit, found only when CI failed at merge.
- **Reading a TSL variable after reassigning it reads the new value.** A
  weight worked out from a `toVar()` density and stored for later was read
  after the density had been overwritten, so two rounds of lighting
  changes did nothing. Snapshot it with its own `toVar()`.

## Still open (12 Nov 2026)

- The storm's wall is broad soft bands close to; only the nearest cloud
  gets the close detail.
- A sharp approach without the horizon band.
- Away from the storm the layer is heaps over a sheet, where real photos
  show a near-continuous deck whose swirls are colour and soft relief.
- None of it has been judged in real-time motion or on WebGL2.
