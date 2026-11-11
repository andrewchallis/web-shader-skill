# Sky, atmosphere and haze: one model, composed once

How to build a planet's sky, edge glow and haze so they agree with each
other and with the surface or cloud under them. Read before adding any
air, haze or fog layer, and when an edge glow or haze "floats" over the
thing it should belong to.

Source: ideas from a Three.js WebGPU/TSL sky skill
("threejs-sky-atmosphere-and-haze") that Andrew found on 11 Nov 2026. Its
author and licence weren't given, so this page restates the ideas in our
own words and adds what we learned on Elsewhere's Jupiter. No text or code
is copied from it.

## 1. Pick one branch and say what it claims

| Need | Branch | What it can claim |
| --- | --- | --- |
| A local sky, distance fog or height fog in a bounded scene | Sky dome plus TSL fog | An authored look, nothing physical |
| A planet seen from orbit to the ground, with a moving camera and Sun | Small precomputed tables (transmittance, multiple scattering) plus a short march per pixel, in the style of Hillaire | Approximate physical scattering |
| A fixed atmosphere that must be very accurate | Bruneton-style scattering orders, or an offline solve | Accuracy checked against a reference |

Use the table branch for anything a camera flies through. Keep an offline
integrator for reference images, not for runtime pixels.

## 2. One model, one set of units

- One length unit for radii, positions and march steps. Store extinction
  and scattering per that unit, so `beta * ds` has no units.
- One body frame, one Sun direction convention, one colour basis.
- Transport data is linear (no colour space); keep radiance scene-linear
  until the one final output stage. Tone mapping runs once.
- Every layer that draws air (edge glow, haze over the disc, fog inside
  clouds) reads the same model. Separate hand-tuned layers for each height
  range drift apart: each gets its own colour and lighting, and they show
  as bands or pops where they hand over.

## 3. Compose over the surface exactly once

For a visible surface or cloud behind the air, the result is:

```text
C_out = C_surface * T_segment + S_segment
```

`T_segment` is how much light gets through the air between the camera and
the surface; `S_segment` is the light the air scatters towards the camera
along that segment. With blending this is premultiplied: source = S,
destination multiplied by T. A grey T (one value) is a cheap version; a
per-colour T needs a multiply pass before the add.

Rules that follow:

- The air must dim what is behind it by the same amount its own glow
  implies. Adding the glow but only part of the dimming makes a bright band
  that floats over the surface, worst at the edge where the path is longest.
- Stop the segment at the first opaque surface. Don't carry the march on
  past a cloud top into the far side of the shell; at a grazing edge that
  long extra path is a bright line.
- For a sky pixel (nothing behind), sample sky radiance and the Sun disc.

## 4. Nothing applied twice

List every factor that can act on a pixel and make sure each acts once:
the surface's own limb darkening, haze painted into its texture, any haze
the cloud shader adds, the air's dimming, the air's glow, a tint taken
from the surface colour, cloud shadows, direct Sun dimming. A typical bug
is the surface darkened twice (its own haze plus the air's T) or lit
twice (Sun dimmed in the cloud shader and again by the air).

When another system takes lighting from the atmosphere (Sun colour at a
point, sky light on a normal), hand over one form only: either direct Sun
already dimmed by the air, or the raw Sun plus the transmittance, never
both.

## 5. Make tables only for what reads them

Build a table (transmittance, multiple scattering, sky light, sky view,
aerial 3D) only when something samples it. Base tables depend on the
atmosphere and body; they shouldn't rebuild when only the camera moves.
Aerial tables depend on camera pose, projection and viewport. If the app
must also run on WebGL2, avoid WebGPU-only compute products, or keep a
fallback.

## 6. Checks

- **Zero-atmosphere control:** with air density 0, the frame must equal
  the plain surface (within one brightness level). Cheap, catches a layer
  that adds light on its own.
- Fixed-view stills: sky, horizon, night side, haze over the surface, and
  the view from outside the planet.
- Hand-overs between near and far shells or between a shell and a
  post-process: no pop in a fly-through.
- Table look-ups at their seams (horizon split, wrap-around).

## Symptoms

| Symptom | Look at |
| --- | --- |
| Bright band at the lit edge that ignores the surface's edge darkening | air glow added without its full dimming; march running past the surface; several air layers stacked |
| Glow on the side away from the Sun | phase function sign |
| Haze changes when the world is scaled | unit conversion of extinction |
| Seam or pop at the horizon or a hand-over | table seam, ray-body interval, two layers owning the same height |
| Surface too dark under haze | dimmed twice |
| Camera jitter rebuilds base tables | dependency keys too broad |
| Haze too short off-axis | depth used as ray length without converting |

## Elsewhere's Jupiter (11 Nov 2026, in progress)

Jupiter had four separate air and haze pieces (an edge haze sphere, a
globe air shell, the cloud deck's physically based air, and fog inside the
close clouds), each tuned for its own heights. From orbit a grey-blue band
showed at the lit edge. Hiding the edge haze and the globe air left the
band, so it was the deck air itself. Haze over the disc from orbit didn't
remove it either. The deck air added its full glow but dimmed the cloud
behind it by only half (a dim factor of 0.5), which breaks section 3.
Being tested: the full blend, a very thin haze (the reference photos show
the edge haze faint and never brighter than the cloud beside it), and
stopping the march at the cloud top. Update this section with the result.
