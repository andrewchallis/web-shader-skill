---
name: web-shader-rendering
description: Lessons for look-driven shader work in Three.js on WebGPU and WebGL2 (TSL node materials), above all ray-marched volumes - planet and gas giant clouds, atmospheres and haze, nebulae, gas. Use before writing, tuning or debugging such a shader, when a render "looks wrong" (pebbles, grain, fuzz, bands, seams, black frames, double horizons), or when planning how detail should change with camera distance.
---

# Web shader rendering

Hard-won lessons from about 100 rounds of cloud, atmosphere and gas work on
planets, gas giants and nebulae in Three.js (WebGPU first, WebGL2 fallback),
written so they carry over to any project. For TSL and WebGPU API syntax,
use an API reference such as Dan Greenheck's
[webgpu-threejs-tsl skill](https://github.com/dgreenheck/webgpu-claude-skill);
this skill is about technique, look and process.

If the project has its own shader notes (a project skill, docs on its
harness and evidence rules), read those too: they win over this skill.

## Defaults that held up

These are starting points, not laws. Most came from planet clouds seen from
orbit down to skimming height. Decide which ones fit the scene you're
building, and when you break one, say why in the code or PR. A single-distance
shot doesn't need rule 1; a stylised look may not want rule 2; a tight GPU
budget may beat rule 3.

1. **One renderer from far to close.** Every visible jump we hit came from a
   handover between two renderers that didn't agree. Grow detail inside one
   shader instead, faded in by on-screen size. Where a handover can't be
   avoided, hand over only where the two already look the same, and check it
   in motion.
2. **The far look is the map.** At distance the texture (or the far
   renderer) is the truth. The near shader uses it as coverage, height and
   colour, and finer noise only *wears its edges*. Then big shapes stay put
   as detail comes in.
3. **Add detail by pixel footprint, not by distance.** Fade each noise
   octave in once its cells cover a few pixels; fade it out below that.
   Unresolved octaves read as grain, gravel or fuzz.
4. **Contrast comes from Sun shadow, not ambient.** High sky or ambient
   light makes everything flat and pale. Cut ambient hard, march a few steps
   towards the Sun, add a small share of multiple scattering.
5. **Copy the reference faithfully before adapting it.** When someone hands
   you a shader or paper, port it line for line first (in TSL, with the
   licence checked), match its frames, then fit it. Loose "inspired by"
   rebuilds wasted dozens of rounds.
6. **Judge on rendered frames from a hardware GPU.** Source reading, numbers
   and software renderers (SwiftShader, llvmpipe) can't prove a look.
   Stills can't prove motion. Use stills to iterate, then a fly-in video.
7. **Compare against a benchmark image every round.** Put the candidate
   beside the reference at the same height, Sun angle and framing. Describe
   in words what differs before changing code.
8. **If attempts keep missing, change approach, not knobs.** After three
   rounds that don't close the gap, stop tuning and rethink the structure
   (or go back to rule 5).

## Workflow for a look change

1. Name the visible goal, the exact view (height, pitch, Sun angle) and the
   benchmark. Capture a baseline.
2. Prototype in an isolated harness that shows one object with no app boot
   (seconds per edit, not minutes). URL or JSON knobs for height, Sun, look.
3. Shoot a **height ladder** (for example 1, 1/2, 1/4, 1/8, 1/16 of the
   radius, skim and straight-down) and a side-by-side of 2 to 3 variants per
   round. One still per height: a two-frame jump gets smeared by motion blur.
4. Diagnose with tints: paint each layer or band a flat colour, exaggerate
   detail, show where each fade weight is 0 or 1. Bisect with flags that
   switch layers off.
5. When stills are right, record a slow **fly-in** through every band. Look
   for brightness jumps (measure mean frame brightness; we kept steps under
   about 4/255), soft patches between bands, shapes that pop or slide.
6. Check the WebGL2 fallback, look for link errors, and time it on the
   target GPU.

## References in this skill

- [references/clouds-by-altitude.md](references/clouds-by-altitude.md):
  what to draw in each altitude band of a planet, with techniques and
  sources.
- [references/ray-marching.md](references/ray-marching.md): march
  structure, camera inside a shell, grazing rays, lighting, cost.
- [references/symptoms.md](references/symptoms.md): what a bad frame looks
  like, its cause and the fix. Read this first when debugging a look.
- [references/webgpu-webgl2.md](references/webgpu-webgl2.md): TSL and
  backend gotchas, WebGL2 limits, precision, pipeline count, software
  renderer traps.
- [references/prior-art.md](references/prior-art.md): full open-source
  cloud renderers (takram three-clouds, joshbrew WebGPU clouds) and what
  to take from each. Read before designing a new cloud renderer.
- [sources/](sources/README.md): original shader code we were given, with
  licences and where each one is ported.

## Sources you can't open

The links in these files are credit and a pointer, not something you need
to read. Each technique is described well enough here to build from.
Sandboxed agents often can't reach Shadertoy, papers or personal sites (a
cloud proxy blocked every one we tried). When you do need the original
code or text:

1. Look in [sources/](sources/README.md), then for a local copy or an
   existing port in the project you're working in.
2. Try a browser the human runs, if you have one.
3. Otherwise ask the human to paste it (for Shadertoy: every tab, including
   Common and Buffers, plus the licence line). Save what they paste beside
   the other references, with its URL, author, date and licence, so the
   next agent doesn't ask again.

Never guess at code you couldn't read and call it a port.

## Licences

Port ideas into your shader language; don't paste code you can't licence.
Shadertoy's default is CC BY-NC-SA 3.0: adapting needs attribution and makes
the result non-commercial. GPL sources are ideas only. MIT needs the notice.
Record every adapted source in a code comment and the project's third-party
notices.
