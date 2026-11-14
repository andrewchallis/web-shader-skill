# Web shader rendering skill

A Claude Code skill with lessons for look-driven shader work in Three.js
on WebGPU and WebGL2 (TSL node materials): ray-marched planet and gas
giant clouds, atmospheres and haze, nebulae and gas. It came out of about
100 rounds of cloud and gas work on a space documentary web app, and
records what worked, what failed and why.

It covers technique and process, not API. Pair it with an API reference
such as [webgpu-threejs-tsl](https://github.com/dgreenheck/webgpu-claude-skill).

## Install

```
/plugin marketplace add andrewchallis/web-shader-skill
/plugin install web-shader-rendering@web-shader-rendering
```

Or copy `skills/web-shader-rendering/` into a project's `.claude/skills/`.

## Contents

- `SKILL.md`: defaults that held up, and the look-dev workflow.
- `references/clouds-by-altitude.md`: what to draw from orbit down to
  skimming height.
- `references/earth-surface-streaming.md`: surface imagery, tile budgets,
  camera controls, local frames, atmosphere and terrain.
- `references/earth-cloud-transitions.md`: shared cloud fields and the
  globe-to-volume transition.
- `references/gas-giant-clouds.md`: the Jupiter record: what worked and what didn't, orbit to skim.
- `references/gas-giant-snippets.md`: TSL snippets for the key Jupiter pieces.
- `references/cloud-types.md`: the ten Earth cloud types (from CK42BB, MIT) and gas giant overlap.
- `references/ray-marching.md`: shells, grazing rays, density, light, cost.
- `references/symptoms.md`: bad frame, cause, fix.
- `references/webgpu-webgl2.md`: TSL and backend gotchas.
- `references/prior-art.md`: open-source cloud renderers worth studying.
- `sources/`: original shader code whose licence allows sharing.

## Three.js skill pack

The plugin also carries 27 `threejs-*` skills from
[linegel/threejs-complete-set-of-skill](https://github.com/linegel/threejs-complete-set-of-skill)
(commit `e3c9563`), copied unchanged into `skills/`. They cover the wider
Three.js WebGPU/TSL stack: procedural geometry, materials, fields, planets,
vegetation, buildings and creatures; sky, clouds, spectral ocean, water,
rain and snow; shadows, ambient occlusion, bloom, exposure and the image
pipeline; cameras, particles, motion, debugging and visual validation.
Start with `threejs-choose-skills`, which picks the smallest set for a task.

Installed through the plugin, they're named
`web-shader-rendering:threejs-<topic>`, for example
`/web-shader-rendering:threejs-spectral-ocean`.

## Updates

A workflow raises the patch version in `.claude-plugin/` after every merge
to main, so installed copies see a new version and update. Don't bump it by
hand in PRs.

## Licence

The skill's own text is MIT. Files in `sources/` keep their authors'
licences, given in each file's header.
`references/cloud-types.md` and `references/ck42bb-procedural-clouds.md` are adapted from Kingsley (CK42BB)'s
procedural-clouds-threejs skill, MIT; the notice is at the end of each file.
The `skills/threejs-*` folders are ISC-licensed by the Three.js WebGPU Skill
Pack contributors; each keeps its own `LICENSE` file.
