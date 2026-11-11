# WebGPU, WebGL2 and TSL gotchas

TSL compiles to WGSL (WebGPU) and GLSL ES 3.0 (WebGL2). Things that work on
one backend can fail on the other, and on one GPU driver but not another.

New to raw WebGPU? [WebGPU explained](https://dev.to/biomathcode/webgpu-explained-the-browsers-new-graphics-and-compute-engine-1cld)
(Pratik Sharma, dev.to, July 2026) is a plain introduction: adapter and
device, explicit pipelines and bind groups, command encoding, WGSL and
compute shaders, compared with WebGL's state machine. Background only; it
has no TSL or Three.js specifics.

## WebGPU tools and links

For tools and examples beyond this skill, [awesome-webgpu](https://github.com/mikbry/awesome-webgpu)
(CC0 list, a51bb94, checked Nov 2026) is the general index. Every entry that
can help shader look, cost or debugging work is below, grouped by use. Left
out on purpose: AI/ML runtimes (WebLLM, ONNX, Transformers.js, Web Stable
Diffusion), native C/C++/Rust/.NET bindings and engines (Dawn, wgpu, sokol,
wgpu-native, WebGPU-C++, Vienna engine, Emdawnwebgpu, React Native WebGPU,
Deno), charting (ChartGPU), MATLAB (RunMat), photo editors and 2D vector
(Darkly, Vello, PixiJS, fisheye.js), games (Spookyball), memory-model
testing, community/bug-report links and the historical section.

### Debug and profile

- [webgpu-inspector](https://github.com/brendan-duncan/webgpu_inspector):
  browser extension that captures a frame and shows every pipeline, shader,
  buffer and texture, with GPU timing. The WebGPU counterpart of Spector.js
  (which only sees WebGL). First stop for "which pass costs what".
- [WebGPU Dev Extension](https://github.com/greggman/webgpu-dev-extension)
  (greggman): validation messages with call sites, memory tracking (find
  leaked render targets) and redundant-state warnings.
- [WebGPUReconstruct](https://github.com/Chainsawkitten/WebGPUReconstruct):
  records the browser's WebGPU calls and replays them natively, so desktop
  tools (Nsight, RenderDoc, PIX) can profile one frame.
- [WebGPU timestamps](https://amirsojoodi.github.io/posts/WebGPU-Timestamp/)
  (Amir Sojoodi): how timestamp queries work, for per-pass GPU timing.
- [wgsl_reflect](https://github.com/brendan-duncan/wgsl_reflect): parses
  WGSL and lists bindings, structs and entry points. Handy for checking what
  TSL generated (bindings per pipeline, struct layouts).

### Performance and best practice

- [WebGPU texture best practices](https://toji.dev/webgpu-best-practices/img-textures)
  and [buffer upload best practices](https://toji.dev/webgpu-best-practices/buffer-uploads)
  (Brandon Jones): image loading, mipmap generation, formats,
  `writeBuffer` vs mapped staging buffers. Read before streaming tiles.
- [Efficiently rendering glTF models](https://toji.dev/webgpu-gltf-case-study/)
  (Brandon Jones): pipeline caching and grouping draws by pipeline, the same
  "fewer distinct pipelines" lesson as TSL below.
- [Figma rendering: powered by WebGPU](https://www.figma.com/blog/figma-rendering-powered-by-webgpu/)
  (2025): a real migration with shaders, batching and WebGL fallback.
- [From WebGL to WebGPU](https://developer.chrome.com/docs/web-platform/webgpu/from-webgl-to-webgpu)
  (Google) and [From WebGL to WebGPU in Construct](https://www.construct.net/en/blogs/ashleys-blog-2/webgl-webgpu-construct-1519)
  (Ashley Gullen): the differences that bite when one code path serves both
  backends (clip-space Z, Y flip, uniform layout, no global state).
- Chrome release notes: [compatibility mode and transient attachments](https://developer.chrome.com/blog/new-in-webgpu-146)
  (Chrome 146: WebGPU on older GPUs; transient attachments save memory and
  bandwidth for depth/MSAA targets that never leave the pass) and
  [immediates](https://developer.chrome.com/blog/new-in-webgpu-149-150)
  (Chrome 149-150: small per-draw values without a uniform buffer).
  Check Three.js support before relying on either.
- [spark.js](https://ludicon.com/sparkjs/) (Ludicon): real-time GPU texture
  compression to BC/ASTC/ETC. Its [demo](https://ludicon.com/sparkjs/gltf-demo/)
  compares KTX2 against AVIF + spark. An option where KTX2 baking is awkward
  (generated or streamed textures); check its licence before use.
- [webgpu-utils](https://github.com/greggman/webgpu-utils): mipmap
  generation, buffer layouts from WGSL, bind group helpers.

### Learning WebGPU and WGSL

- [WebGPU Fundamentals](https://webgpufundamentals.org/): the most complete
  article set (compute, textures, mipmaps, timing, optimisation).
- [Tour of WGSL](https://google.github.io/tour-of-wgsl/) and the
  [WGSL spec](https://www.w3.org/TR/WGSL/) ([editor's draft](https://gpuweb.github.io/gpuweb/wgsl/)):
  for reading what TSL emits.
- [WebGPU spec](https://gpuweb.github.io/gpuweb/), [explainer](https://gpuweb.github.io/gpuweb/explainer/),
  [MDN](https://developer.mozilla.org/en-US/docs/Web/API/WebGPU_API),
  [webgpu.rocks](https://webgpu.rocks/) quick reference,
  [WebGPU.org](https://webgpu.org/), [Chrome WebGPU docs](https://developer.chrome.com/docs/web-platform/webgpu),
  [caniuse](https://caniuse.com/webgpu) for browser support.
- [WebGPU: all of the cores, none of the canvas](https://surma.dev/things/webgpu/index.html)
  (Surma) and [GPU compute on the web](https://developer.chrome.com/docs/capabilities/web-apis/gpu-compute)
  (François Beaufort): compute shaders, workgroups, buffers.
- [Your first WebGPU app](https://codelabs.developers.google.com/your-first-webgpu-app)
  (Google codelab), [WebGPU for Dummies](https://people.distributive.network/amir/WebGPU-For-Dummies.html),
  [From 0 to glTF](https://www.willusher.io/graphics/2023/04/10/0-to-gltf-triangle/) (Will Usher),
  [Learn vgpu](https://endash.us/apps/learn-vgpu), [Learn wgpu](https://sotrh.github.io/learn-wgpu/)
  (Rust, but the same concepts), Jack Xu's book
  [Practical WebGPU Graphics](https://books.google.com/books?id=tPQyEAAAQBAJ) and video series
  ([Dr. Xu](https://www.youtube.com/playlist?list=PL_UrKDEhALdKh0118flOjuAnVIGKFUJXN),
  [Genka](https://www.youtube.com/playlist?list=PLnTPVrg9-a1Ou2KXUniDr1HC7qgL2JD2x),
  [SketchpunkLabs WebGL to WebGPU](https://www.youtube.com/playlist?list=PLMinhigDWz6f5Nm_GYGREYnaf9mzoNdjX),
  [Google intro](https://www.youtube.com/watch?v=m6T-Mq1BPXg),
  [Babylon's perspective](https://www.youtube.com/watch?v=A2FxeEl4nWw)).
- [PBR in WebGPU](https://tchayen.com/pbr-in-webgpu-implementation-details)
  (Tomasz Czajecki): BRDF, IBL prefiltering and LUTs in WGSL.
- [Build a compute rasterizer](https://github.com/OmarShehata/webgpu-compute-rasterizer/blob/main/how-to-build-a-compute-rasterizer.md)
  (Omar Shehata): drawing points/triangles from compute with atomics, the
  base for huge star or particle counts.
- [WebGPU Experts blog](https://www.webgpuexperts.com/blog), [r/WebGPU](https://www.reddit.com/r/webgpu/): news.

### Shader tooling and playgrounds

- [compute.toys](https://compute.toys/): Shadertoy for WGSL compute. Many
  volumetric, fluid and noise shaders to read.
- [Shadeup](https://shadeup.dev/), [Online WGSL editor](https://takahirox.github.io/online-wgsl-editor/),
  [WebGPU Live Demo Editor](https://www.wgsl.dev/editor), [WebGPU-Playground](https://06wj.github.io/WebGPU-Playground/),
  [Shader Graph WGSL](https://deepkolos.github.io/shader-graph-wgsl/) (node editor):
  quick places to try a WGSL fragment away from the app.
- [munrocket's 2D](https://gist.github.com/munrocket/30e645d584b5300ee69295e54674b3e4)
  and [3D SDF primitives](https://gist.github.com/munrocket/f247155fc22ecb8edf974d905c677de1)
  in WGSL: Inigo Quilez's distance functions ported, ready to turn into TSL.
- [TypeGPU](https://docs.swmansion.com/TypeGPU/), [WESL](https://github.com/webgpu-tools/wesl-spec)
  (`import`, `@if` for WGSL), [vgpu](https://vgpu.sh/), [WebGpGpu.ts](https://github.com/eddow/webgpgpu),
  [Thimbleberry](https://github.com/mighdoll/thimbleberry) (reusable shaders:
  prefix sum, histogram, reduce, image transforms, [demo](https://thimbleberry.dev)):
  ideas for raw-WGSL compute helpers when TSL is not enough.
- Other engines' WebGPU paths to compare tricks with:
  [Babylon.js](https://doc.babylonjs.com/setup/support/webGPU) ([playground](https://playground.babylonjs.com/)),
  [PlayCanvas](https://playcanvas.com/) ([demos](https://playcanvas.vercel.app/)),
  [luma.gl](https://luma.gl/), [RedGPU](https://github.com/redcamel/RedGPU),
  [zephyr3d](https://zephyr3d.org/), [Use.GPU](https://usegpu.live),
  [GEngine](https://github.com/GEngine-js/GEngine), [hwoa-rang-gpu](https://github.com/gnikoloff/hwoa-rang-gpu),
  [RedCube](https://github.com/Reon90/redcube) (glTF viewer).

### Demos worth reading for techniques

- [Three.js WebGPU examples](https://threejs.org/examples/?q=webgpu): the
  quickest working reference for a TSL node or compute pattern.
- [WebGPU Samples](https://webgpu.github.io/webgpu-samples/) (official):
  compute boids, particles, shadow maps, deferred, cubemaps, timestamps.
- [WebGPU 2D fluid](https://github.com/kishimisu/WebGPU-Fluid-Simulation)
  (kishimisu): stable fluids in compute, a base for a baked gas or storm
  motion field.
- [WebGPU-Lab](https://s-macke.github.io/WebGPU-Lab/) (Sebastian Macke):
  compute experiments incl. fluid, light propagation and path tracing.
- [WebGPU Particles](https://hsimpson.github.io/webgpu-particles/),
  [Points](https://github.com/Absulit/points) ([examples](https://absulit.github.io/points/examples/index.html)):
  GPU particle update and multi-pass render patterns (star fields, dust).
- [WebGPU Metaballs](https://toji.github.io/webgpu-metaballs/) (compute
  marching cubes) and [Marching Cubes WebGPU](https://conorpo.github.io/marching-cubes-webgpu/):
  meshing a density field, e.g. a gas cloud surface.
- [Clustered shading](https://toji.github.io/webgpu-clustered-shading/) and
  [Sponza](https://toji.github.io/webgpu-test/) (Brandon Jones): many lights,
  WebGL vs WebGPU comparison.
- [WebGPU path tracing](https://iamferm.in/webgpu-path-tracing/),
  [Web-RTRT](https://github.com/C-none/Web-RTRT/) (ReSTIR), [WebRTX](https://github.com/codedhead/webrtx)
  and [Shadowray](https://www.shadowray.gl/): ray tracing in compute.
  Reference images more than shipping paths at our frame budget.
- [Tarek Sherif's WebGPU examples](https://tsherif.github.io/webgpu-examples/),
  [wgpu examples](https://wgpu.rs/examples/), [Forest WebGPU](https://www.babylonjs.com/Demos/WebGPU/forestWebGPU.html)
  (Babylon, many instanced trees), [DoG Studio](https://dougfenstermacher.com/dogpack/)
  (Difference-of-Gaussians filters, image post),
  [vgpu shader on live HTML](https://html-in-canvas.dev/demos/vgpu-shader/) (flagged API).

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
- three.js `resolveTimestampsAsync` (r186) returns the GPU time of the
  newest frame it resolved, not a total since the last resolve. Don't
  divide it by the frames in between: that read 2-3x low on a slow scene.
  When frame time is far above the GPU readout, take a Chrome trace: a
  `Queue::Submit` blocking most of the frame means the GPU is the limit.
- One bloom or post node per scene pipeline multiplies passes; share them.
- three's `dFdx`/`dFdy` emit WGSL `dpdx`/`dpdy`, which Chrome may run
  coarse (one value per 2x2 quad). For per-pixel slopes, a small TempNode
  can emit `dpdxFine`/`dpdyFine` on WebGPU and `dFdx` on WebGL2 (check
  `builder.renderer.backend.isWebGPUBackend`).
- WGSL error "structures must have at least one member" on
  `struct OutputType` means a node material's fragment stage came out
  with no outputs. Its pipeline is invalid, the command buffer it is
  encoded in is rejected ("Invalid CommandBuffer ... due to a previous
  error"), and every draw in that submit is lost. WebGL2 compiles the same
  material without a word, so read the WebGPU console on every new layer.
  Seen with Earth's close layers on (four MeshBasicNodeMaterials), not
  with them off. The material behind it wasn't identified yet.

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
