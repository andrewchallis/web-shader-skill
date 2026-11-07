# Source shaders

Original shader code, kept so agents that can't reach Shadertoy still
have it. Read for ideas, port to TSL, credit the author.

Only code whose licence allows sharing is copied here. CC BY-NC-SA and
unknown-licence code stays out; the table below says what it is good for,
so you can ask a human for the original if you need it.

| File | Source | Licence | Good for |
| --- | --- | --- | --- |
| [fast-atmosphere-clouds.glsl](fast-atmosphere-clouds.glsl) | Felix Westin, Fast Atmosphere ([lcfSRl](https://www.shadertoy.com/view/lcfSRl)), cloud parts | MIT (notice in file); `CloudShape` from csSfRK left out (unknown licence) | map as coverage with edges carved by finer noise; cheap 4-step Sun light |
| [dathor-dust-pillars-volume.glsl](dathor-dust-pillars-volume.glsl) | dathor, Where James Webb Cannot Reach ([7XyXRV](https://www.shadertoy.com/view/7XyXRV)), Volume A tab | "Free for anyone to use"; Hoskins hashes MIT | baking a tileable SDF of columns on a turbulent floor into a 3D texture |
| [dathor-dust-pillars-march.glsl](dathor-dust-pillars-march.glsl) | same, Buffer A march and shading (no backdrop or stars) | same | adaptive steps, light visibility taps, rim glow, lit smoke floor |

Not copied here (CC BY-NC-SA 3.0: adapting needs credit and makes the
result non-commercial):

| Source | Good for |
| --- | --- |
| Duke, Volumetric explosion (lsySzd) | ridged spiral noise billows round a sphere, density colour ramp |
| Jerome Liard, Overcast Cloud (tl33Rn) | low-Sun cloud light: warm tops, long soft shadows |
| Shane, Cheap Cloud Flythrough (Xsc3R4) | very cheap flythrough clouds in a thin layer |

To add one: put the code in a file named `<author>-<what>.glsl` with a
header giving URL, author, date, licence and what it is good for, and add
a row above. Record it in your project's third-party notices if you port
any of its code.
