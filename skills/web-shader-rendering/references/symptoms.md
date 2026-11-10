# Symptoms, causes and fixes

Read this first when a frame looks wrong. Each row happened at least once
in our cloud and gas work.

| What you see | Usual cause | Fix |
| --- | --- | --- |
| Visible jump or seam at one height or distance | Handover between two renderers that don't match in shape, colour or brightness | One renderer with detail grown in; or hand over only where they already match. Measure brightness of the two separately (globe-only vs close-only flags). |
| Pebbles or popcorn on a flat floor | Small separate shapes (puffs, carved banks, alpha shells) with nothing joining them; height clamped at the floor | Continuous deck from the map's height; soft floor with haze; puffs bigger and fewer |
| Gravel, grain, hairs, fuzz, cotton wool | Octaves finer than a few pixels on screen | Fade octaves by pixel footprint; make close-in detail several times bigger |
| Fish scales, leopard spots, regular rows | One noise octave dominating, cells all one size, or shading from cells that aren't resolved | Mix sizes, rotate octaves against each other, fade shading with relief |
| Flat facets on slopes | Finite differences of a trilinear-filtered baked texture (piecewise linear) | Analytic derivatives of computed noise, or central difference across a whole puff |
| Blotches, cells or stacked sheets inside the cloud; edges glow | Long camera-relative steps through sharp-edged cloud (each step draws as a slice rim), and cellular noise borders read as cell walls | Finer, world-anchored steps near surfaces with edges that widen with distance; Perlin-Worley billows added to a 3D SDF instead of cellular carve noise (see Nightscape in prior-art.md) |
| Painted sand ripples | Smooth fractal noise used as shading with no real height | Real height or drop it |
| Vertical streaks at a low Sun | Tall straight-sided height-field columns (towers) | Rounded billows that vary up the walls, or lower relief |
| Smears along one axis | Noise stretched too far along a band, viewed along it | Stretch near 1 to 1.5 |
| Solid surface with cracks | Cloud too dense with sharp edges | Thinner, softer cloud |
| Black frames during a fade | An opaque layer's depth hides the volume; or the volume starts from the shell's outer face from inside | No depth writes while fading; march from the camera |
| Black floor or black sky low down | Camera inside a shell drawn FrontSide only, or near plane clips it | DoubleSide/BackSide inside; inner ball for floor rays |
| Second horizon above the real one | Grazing rays ran out of steps and were shaded in mid-air | Detect missed rays, fall back to a stand-in hit |
| Pale band at the horizon or along the lit limb | Haze falls off too slowly with height; bright far air shell | Faster haze falloff; low air shell exposure |
| Grey mush at a low Sun | Cloud colour not tinted by Sun angle | Tint light and ambient by Sun elevation; more forward scattering near the horizon (from the CK42BB clouds skill) |
| Flat and pale | Ambient or sky light too high | Cut ambient, rely on Sun shadow |
| Half-lit under a low Sun | Light term too flat at grazing angles | Full cosine falloff, smaller scatter share |
| Shapes flow like liquid with the camera still | Field clock too fast for close views | Slow the clock (separate churn from camera motion first) |
| Glowing dome or grey fog over everything | Density added before the threshold, or broad extra layers | Add density after the threshold, keep extra layers thin |
| Far frame correct, close look grey or flat | Camera offset lost in float32 shader matrices when very close to a huge object | Pass the eye position from JS (double precision) as a uniform, relative to the object |
| Port of a reference looks dull | Output went through sRGB or tone mapping the original didn't use | Match the original's output (linear, its own grade) before judging |
| Clouds shimmer, boil or slide as the camera moves | Samples at fixed distances from the camera slide through the cloud; per-frame jitter | Sample on world-anchored planes; no per-frame randomness in shape; temporal accumulation for noise |
| Thin far wisps flicker or pop | Edge density ramp as sharp far away as close up; hard far limit | Widen the edge ramp with distance; fade cloud out over the end of the march |
| Flat strip under the sky at the horizon, with a hard straight top: a second horizon | An air shell switched on for a look that lacks the shell's ground-edge settings, so the air meets the cloud tops on a hard edge | Carry the ground-edge softening with the air (soft fade of the air near the cloud tops, a few pixels wide), and check the limb with a 4x crop |
| Bright striped band along the far cloud row, or a pale hard-edged band at the horizon, after an "anti-slice" tweak | Finer inside steps or a softened step size make grazing rays draw each step as its own layer at the horizon | Judge anti-slice settings at grazing views, not only looking down; fix slicing with world-anchored planes instead |
| Procedural detail crawls across the land as a globe turns | Noise read at the mesh position while the globe turns by sliding its map coordinate | Feed noise the planet-fixed direction of the spun map coordinate |
| Thin dark dotted dashes along straight lines on near terrain | Lighting from the screen slope of the whole height (guide and big octaves) | Mesh normal for big shapes, screen slope only of detail finer than the mesh (procedural-terrain.md) |
| Near terrain grain or 2-pixel-tall bars when skimming | Per-pixel lit octaves too fine for a slanted pixel's long side | Light per pixel only waves of ~20 px, faded by footprint / cos(view to ground) |
| Fine diagonal hatching on lit terrain | Smoothstep inside each texel of a baked noise texture (flat spots per texel) | Plain trilinear, and light per pixel only well-sampled octaves |
| Near relief "smooth" but suddenly busy when a constant changes | Area clamp in the screen-slope normal flattening close relief | Clamp far below the pixel area at the closest view |
| Valley fog fills deserts and canyons like cumulus | Fog from depth below average ground only | Gate by ground type from the map colour; thickness over the view's slant; wavy tops |
| Change "did nothing" | Wrong layer is the one drawing at that height, or a guard hid it | Tint layers flat colours to see which one draws |
