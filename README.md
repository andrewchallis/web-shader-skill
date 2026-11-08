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
- `references/ray-marching.md`: shells, grazing rays, density, light, cost.
- `references/symptoms.md`: bad frame, cause, fix.
- `references/webgpu-webgl2.md`: TSL and backend gotchas.
- `references/prior-art.md`: open-source cloud renderers worth studying.
- `sources/`: original shader code whose licence allows sharing.

## Licence

The skill's own text is MIT. Files in `sources/` keep their authors'
licences, given in each file's header.
