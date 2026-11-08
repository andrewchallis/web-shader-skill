# Clouds by altitude

Heights are rough and scale with the planet radius R. On a gas giant
(Jupiter R = 71,492 km) 0.05 R is about 3,500 km. The bands are where the
look *needs* to change; prefer growing detail in the same renderer (see
SKILL.md rule 1). A globe shader and a local volume can also work together
when they share coverage, coordinates, light and a checked compositing
transition. See [Earth cloud transitions](earth-cloud-transitions.md) for
one inspected implementation; its Earth thresholds do not scale directly
to gas giants.

## Orbit: above about 1 R

- The texture with proper mips is the look. Don't add noise of your own.
- Near the low end, stochastic texture filtering (one-tap stochastic
  bicubic, [arXiv 2305.05810](https://arxiv.org/abs/2305.05810)) hides map
  pixels. It is a filter, not a cloud method.
- Limb: a thin physically based air shell. Keep its exposure low; a bright
  far air shell draws a glowing band down the lit edge.

## High: about 1 R to 0.25 R

- Treat the map as coverage and height: map brightness sets cloud top
  height (bright zones high, dark lanes low). Finer noise only erodes the
  edges with a remap, so the far shape holds as detail arrives
  (Felix Westin, [Fast Atmosphere](https://www.shadertoy.com/view/lcfSRl),
  MIT).
- Fade each octave in by pixel footprint
  ([webigeo-clouds](https://github.com/Qendolin/webigeo-clouds), GPL, ideas
  only).
- Where a full march is too costly this far out, shade the same height
  field as a lit surface (normal from the height, globe's light) instead of
  marching. It hands over cleanly because it is the same heights.
- Cheap long shadows: a baked 2D shadow map
  ([Terragen Cloud Layer v2](https://docs.planetside.co.uk/wiki/Cloud_Layer_v2)).

## Middle: about 0.25 R to 0.05 R

- One continuous deck: map brightness sets height, darker lanes sink, soft
  floor with haze in the lanes (never clamp at the floor: troughs read as
  holes).
- Billows: Perlin-Worley (SimonDev, Shaders_Clouds1, MIT). Bake a tiling
  Worley field to a 3D texture. Gives cauliflower shapes, no grain.
- Empty-space skipping: coarse steps, step back on first density, then fine
  steps (webigeo-clouds).
- Self-shadow: about 4 steps towards the Sun, plus a share of multiple
  scattering (Fast Atmosphere `Lum()`,
  [Hillaire](https://sebh.github.io)).
- Slope light from analytic noise derivatives
  ([Quilez](https://iquilezles.org/articles/morenoise/)), not finite
  differences of a baked texture.

## Low: skimming, below about 0.05 R

- Low-Sun light: warm tops, soft dimming, long shadows (Jerome Liard,
  [Overcast Cloud](https://www.shadertoy.com/view/tl33Rn), CC BY-NC-SA).
- Silver lining, blue-grey shadow tint, contrast from the colour curve
  (takustaqu/atmosphere, MIT).
- Real cloud shapes close in: erode the deck's edge with 3D inverted Worley
  octaves *in space*, not on the map (the Horizon Zero Dawn / Nubis idea).
  Size matters: small octaves read as fuzz or cotton wool (Jupiter round
  58). Start with cells several times bigger than feels right.
- Storm towers: use height profiles (cumulus, cumulonimbus) you write
  yourself; tall straight-sided height-field columns draw vertical streaks
  at a low Sun.
- In the air: once the camera is inside the haze layer, the sky must glow.
  Draw the air shell's back faces from inside (or march from the camera),
  or the sky goes black as you descend.

## Motion

- Cloud fields need a slow clock. At the speed that looks fine from orbit,
  a close field flows like liquid or plasma. Scale the clock down for close
  views (we ended at a fiftieth of the first pace). When multiple cloud
  renderers overlap, give them the same continuous clock and wind field;
  changing renderer or quality must not reset or relocate the weather.
- Separate churn from camera motion with a frozen-clock clip before tuning
  either.
