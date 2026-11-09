# WebGPU, WebGL2 and TSL gotchas

TSL compiles to WGSL (WebGPU) and GLSL ES 3.0 (WebGL2). Things that work on
one backend can fail on the other, and on one GPU driver but not another.

New to raw WebGPU? [WebGPU explained](https://dev.to/biomathcode/webgpu-explained-the-browsers-new-graphics-and-compute-engine-1cld)
(Pratik Sharma, dev.to, July 2026) is a plain introduction: adapter and
device, explicit pipelines and bind groups, command encoding, WGSL and
compute shaders, compared with WebGL's state machine. Background only; it
has no TSL or Three.js specifics.

## TSL

- An `If()` inside a helper function called several times can give biased
  or wrong results. In helpers, use plain expressions and `select()`.
- JS numbers and callbacks are baked into the generated code. Each distinct
  value makes a new shader and pipeline. Use `uniform()` for anything that
  varies between instances or over time; keep JS constants for true
  compile-time switches.
- Per-instance names in varyings or nodes (for example a varying named with
  an index) also make new pipelines.
- `.toVar()` values you reuse; otherwise TSL may inline and recompute the
  expression at every use.
- Loops: keep counts compile-time constants; `Loop()` with uniform bounds
  costs more and may not unroll.
- A look change in TSL means one shader compile. In a fast harness, show
  compile time separately from frame time.

## WebGL2 fallback

- **Big uniform arrays fail to link on ANGLE over D3D11** (Chrome on
  Windows). A 257-entry table made ten programs fail and the planet drew
  nothing. Use a short `select` chain, a small texture or an analytic fit.
- **Texture units: 16 per fragment stage.** A rich opaque material hits it
  fast. Move extra layers to a second mesh (for example a multiply-blended
  overlay) or pack channels.
- Link failures can show `VALIDATE_STATUS false` with an empty log. Check
  program link status on the target machine; a software renderer may
  compile what the real driver rejects.
- Run every look change with the WebGL2 renderer too before calling it
  done.

## WebGPU

- Pipelines build on first use; hundreds of distinct shaders mean long
  first-load stalls. Precompile (draw hidden before showing) and reuse a
  small set of shader families.
- Timestamp queries need the feature; report "unsupported", not zero.
- One bloom or post node per scene pipeline multiplies passes; share them.

## Precision

- Float32 in shaders can't hold a camera near a planet in a scene built at
  galaxy scale. Do the subtraction in JS (double) and pass the eye relative
  to the object as a uniform.
- Half-float 3D noise textures are fine for shape; derive slope light from
  computed noise when it must be smooth.

## Software rendering (cloud CI, headless)

- SwiftShader and llvmpipe can't run heavy volumes at usable speed (minutes
  per frame for frame-filling noise) and sometimes render them wrongly
  (missing, dimmer, false black). Use them to catch crashes and link
  errors, never to judge a look.
- `gl.finish()` doesn't sync under SwiftShader; a one-pixel `readPixels`
  does.
- Check the actual adapter name every run; an unexpected software adapter
  silently invalidates graphics evidence.
