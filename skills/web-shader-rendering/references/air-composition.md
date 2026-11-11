# Sky, atmosphere and haze: one air, composed once

Adapted from a "threejs-sky-atmosphere-and-haze" skill that Andrew shared on
11 Nov 2026 (author unknown), rewritten for planets seen from orbit down to a
skim, on WebGPU with a WebGL2 fallback. It came in during the Jupiter
"one air" work, when the haze at the planet's edge drew as a glow band.

## Pick one route and say what it claims

| Need | Route | What it can honestly claim |
| --- | --- | --- |
| A local sky or distance/height fog in a bounded scene | An authored sky mesh plus fog in the material | An authored look, not physics |
| A planet's sky, limb and haze over the ground, camera and sun moving | Precomputed transmittance and multiple-scattering tables, single scattering marched per pixel (Hillaire-style) | Approximate, within an error you've looked at |
| A fixed atmosphere where accuracy matters most | Higher scattering orders (Bruneton-style) or an offline solve | Accurate against that reference; keep the offline solve as evidence, not runtime work |

For planets the second route is the default. Marching single scattering per
pixel instead of a 3D aerial-perspective table is fine at screen sizes and
works on WebGL2. Compute-only products (storage textures written by compute
passes) need a WebGL2 fallback or a CPU build, so don't make them the only
path.

## One model

- One length unit for radii, positions and march steps. Keep extinction and
  scattering in its reciprocal unit, so coefficient x step is unitless. A
  haze that changes when the scene is scaled means a missing conversion.
- One sun direction convention (towards the star), one phase convention.
  A halo opposite the sun means a flipped phase sign.
- Every planet's air (Earth, Mars, the giants) shares one material and
  differs only in uniforms, so it compiles to one shader per kind of view.
- Keep radiance scene-linear until the single output stage; tone mapping
  and colour conversion run once.

## Compose: scene x T + S, exactly once

For a surface (ground, cloud tops) seen through air:

    C_out = C_scene * T_segment + S_segment

T is the transmittance along the camera's segment through the air, S the
light scattered towards the camera along it. In a blended material this is
premultiplied alpha: output S as colour and (1 - T) as alpha, with blend
src = One and dst = OneMinusSrcAlpha. A grey alpha carries only the mean
T; a per-colour T needs a second pass (dst x T in rgb, then add S).

Traps:

- **A "dim" knob below 1** (the air adds its full glow but only part of its
  dimming) breaks the rule. Over a surface that darkens towards the edge
  (a gas giant's Minnaert limb darkening) the air then draws a glow band on
  top of the darkened edge. Jupiter, 11 Nov 2026: the band at the lit limb.
- **Thin air means less air**, not a darker or dimmer band: scale the
  density so S and T shrink together. Real giants' limbs (Cassini's
  Jupiter portrait, PIA04866) stay bright cloud right to the edge, with at
  most a faint haze in the cloud's own colour.
- **Stop at the first opaque surface.** Don't carry a ray on past the
  ground's edge into the far side of the shell to soften the horizon: those
  rays pick up the longest, brightest paths, right at the edge.
- **Apply each factor once.** List every factor between the sun and the
  eye: direct sun (already through the air, or the bare source times the
  air's T, never both), sky light, cloud self-shadow and cloud optical
  depth, the ground's own limb darkening, haze painted into a texture map,
  haze a close-up cloud material adds itself, and the camera segment's T
  and S. Each may appear only once. A map photographed from orbit already
  holds the haze over the disc; drawing air over it again from orbit
  doubles it.
- **Zero-air control:** with the air's density at (near) zero the picture
  must match the scene with no air drawn at all, within a brightness level.
  Cheap to keep as a QA switch.

## Hand lighting on, if something else needs it

When clouds or ground take their light from the air, pass only what they
use: the sun direction, the sun already dimmed through the air (or the
bare sun plus the air's T), sky light with a note on whether it includes
the sun's disc, and the camera segment's T and S. Clouds add their own
optical depth, geometry its own shadowing.

## Precomputed tables

- Rebuild the transmittance and multiple-scattering tables only when the
  air's profile or the planet changes, never on camera moves alone.
- Check the table maps at texel centres and edges, at the horizon split and
  across any seam; a pop at the limb or a seam at the horizon points there.
- On WebGPU a compute submission is not completion: wait for the work
  before reading back or reusing a buffer.

## Symptoms

| What you see | Look at |
| --- | --- |
| A glow band at a planet's lit edge, over the darkest cloud | a dim knob below 1; rays run on past the ground's edge; air drawn over a map that already has haze |
| A halo opposite the sun | phase direction sign |
| Haze changes with scene scale | length and coefficient units |
| A seam or pop at the horizon or limb | table seam, the ray's span against the planet, or a hand-over between two shells |
| Ground darkened twice | the sun's dimming applied in both the light and the air |
| Off-axis haze too short | a normalised depth used as a ray length |
