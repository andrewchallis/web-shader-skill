# Ray-marched volumes

Practical structure for clouds, haze and gas drawn on proxy geometry
(a sphere shell or box) in Three.js node materials.

## Proxy geometry and the camera

- **Camera inside the shell.** A FrontSide shell draws nothing once the
  camera is inside it. Use DoubleSide and keep one side per pixel (discard
  back faces while outside), or switch to BackSide when inside. Start the
  ray at the camera, not at the face.
- **Near plane.** Treat the camera as "inside" a little before it really is
  (within a few near-plane distances), or the near plane clips the shell
  and floor rays go black.
- **Far side past the depth range.** Looking down from inside a thin shell
  around a big planet, the shell's far face can be a planet away and get
  clipped. An inner ball just under the cloud floor gives those rays
  something to draw on.
- **Opaque layers under the volume** must not write depth over it while it
  fades in, or their bumps hide the volume and you get black frames at the
  handover.
- **Air from inside.** The same rule applies to atmosphere shells: when the
  camera is inside, draw the inner faces, or the sky goes black.

## The march

- Bound the ray to the shell analytically (ray-sphere for top and floor),
  march only that span.
- Skip empty space in coarse steps; on the first density step back and
  march fine.
- **Grazing rays** near the horizon can run out of steps before reaching
  the cloud. Shading them where the trace stopped (in mid-air) draws a
  second, false horizon. Detect "missed" rays and fall back to a
  stand-in hit, such as the deck's middle height as a sphere.
- Let rays always reach their end; a step budget that silently stops rays
  early shows as bands or holes that change with view angle.
- Jitter the start per pixel (blue noise or a hash) and let temporal
  accumulation or a light blur remove the noise, instead of adding steps.

## Density shape

- Base shape from a height field (the map), soft floor and soft ceiling.
  A soft limit rounds the highest tops; a hard clamp reads as mesas.
- Detail adds or erodes around zero mean, so the average height and colour
  stay those of the map at every distance.
- Density builds over some depth inside the surface (tens of km on a gas
  giant), so tops read as vapour, not rock.
- Too dense plus sharp edges reads as a solid surface with cracks. Thinner,
  softer cloud reads as cloud.

## Light

- Single scattering with a few Sun steps (4 is enough in the middle range,
  up to 6 growing steps for long low-Sun shadows).
- Multiple scattering: a multi-octave approximation (several lobes with
  falling extinction and phase), kept small. Too much makes it flat.
- Ambient / sky light low and tinted by the haze; it fills shadows, it
  doesn't light the cloud.
- Beer-powder or a "powder rim" helps tops facing away from the Sun.
- Haze over the clouds should fall off fast with height; a slow falloff
  draws a pale band above the cloud tops at the horizon.

## Cost

- The full march costs most when it fills the screen. Keep a far level
  (fewer trace and Sun steps) that fades to the full level by on-screen
  size.
- Bake noise to 3D textures (half-float, periodic, octaves rotated against
  each other) instead of computing many fractal octaves per step. Computed
  Perlin is still better for slope light (smooth derivatives).
- Measure GPU time with timestamp queries on the target GPU before and
  after; a still that looks the same proves nothing about cost.
- A single page load's GPU reading can be off by a lot: on a desktop RTX
  in Chrome, the same scene read in one of two states about 9 ms apart
  (about 28 or 37 ms) depending on the load, not the setting. Load each
  variant at least twice, interleaved (A, B, C, then again), and compare
  the lower reading of each. Treat differences smaller than the gap as
  noise. Close views with short frames were steady to about 0.5 ms.
- Judge cost on the real camera path in the app, not only in a lab
  framing: a setting that saved 10 ms at 3,000 km in the lab cost 2-3 ms
  more on a skim that spends its time at 300 km.
- A domain warp or swirl that is fixed in space (a vortex field, hashed
  cell placement) costs its trig per sample, several times per sample if
  the shape is read for slopes and tint too. Bake it once into a texture
  (an offset per point) and read it back.
- When the camera is on rails, bake only what that path can see (the
  corridor and the horizon from it), only when the shot starts, and skip
  the baked branches outside the patch; then prove the bake count stays
  zero on views that can't show it.
