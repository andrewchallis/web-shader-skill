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
| Blocky striped patch or streaks in a thin cloud deck (a few hundred metres thick), unchanged by bake size, layers or step count | Camera-facing sample planes cut the thin deck into slices | Drop the planes for thin decks; plain steps that grow with distance (about t x 0.005), see earth-cloud-transitions.md |
| Contour rings on heaps after dropping sample planes | Plain step too coarse for the heap's sharp edge | Steps about 3x finer; per-pixel start jitter for what remains (untested) |
| Day side of close-up ground drawn as night at some longitudes: black ground and lit streets under sunlit clouds | Lighting from `normalWorld` on a lifted or re-meshed ground patch | Light by the sphere normal from the object-space position, and the view cosine from the camera position (procedural-terrain.md) |
| Whole frames or layers missing on WebGPU only; console shows `struct OutputType` with no members and invalid command buffers | A node material whose fragment stage has no outputs (here a bake quad drawn under the scene pass's MRT); its invalid pipeline sinks the whole submit | Run bakes with `setMRT(null)`, or give the material an output; WebGL2 hides this (webgpu-webgl2.md) |
| Close-up views black on the night side (no lights, ground or cloud) while far views show city lights | The empty-output bake above sank the frame; then the close ground's street lights were too dim from a few hundred km up | Fix the bake; give street light a gain that rises with distance (procedural-terrain.md) |
| Nested cloud: each inner level reads as a dark ball or separate object | Each level accumulated at its own step size, so gas per length scaled as 1/radius | Blend the levels' fields into one, then one density, step and light per sample; gas per length as radius^-0.25 (nebula-fly-in.md) |
| Cloud gets brighter the further in you fly | Longer gas column through the middle; per-step glow not scaled by step length | Glow per step length; exposure table by camera distance holding the median steady |
| Black frame once the camera is inside a puff or dense patch | The puff's density set the step size, so tiny steps ran out before leaving it | Step on the base field's density only; let the puff change what's drawn |
| Radial streaks inside a puff | Fixed (or per-distance) march start offset | Random fraction of the first step per pixel |
| Round bites along dark gaps in a baked field | Octaves finer than a few texels kept in the bake; plain trilinear | Run the finest octaves live in the march; ease the read within each texel |
| Shafts read as a white fog patch, no beams | Light scattered in the march from a transmittance grid: thin sheets' shadows average out along each ray | Screen-space rays cut by the gas pass's opacity, scaled up (nebula-fly-in.md) |
| God rays mirrored top to bottom from their star | Screen UV of a target you drew yourself vs the light's NDC y | Flip y for the light's screen position; check the rays radiate from the sprite first |
| Grey blotches or a grey disc where rays fall | Rays added as their own layer, lit by faint noisy haze; near-light glow over holes | Rays brighten the gas's own colour; no near-light glow without gas |
| A 3D cloud layer draws (debug colour fills the screen) but finds no cloud in the app, while the lab is fine | Its planet-anchored chart was anchored from a camera at the planet's centre (a shader warm-up draw), so it is NaN for good | Never anchor from inside the body; re-anchor when the chart is invalid or far off, and re-bake (earth-cloud-transitions.md) |
| Hard white line just above the horizon, only with the 3D clouds on | The space above the bake's top read as cloud, so rays rising past the horizon hit it | Above the top is clear air; check the signed distance's sign convention |
| Tall vertical spikes or flat-cut columns over thick cloud cover | Heaps taller than the bake's top, cut there | Raise the bake's top above the tallest heap |
| Empty sea, then a full heap field in one frame at the 2D to 3D hand-off | The 3D layer faded in on a timer while its bakes weren't ready | Start bakes well above the fade; ease in over about a second once ready, the 2D layer giving way at the same pace |
| Faint long streaks across the sea from just above a thin high cloud layer | The layer seen edge-on at full strength from half a km above it | Keep it faint from just above its shell |
| Procedural detail crawls across the land as a globe turns | Noise read at the mesh position while the globe turns by sliding its map coordinate | Feed noise the planet-fixed direction of the spun map coordinate |
| Thin dark dotted dashes along straight lines on near terrain | Lighting from the screen slope of the whole height (guide and big octaves) | Mesh normal for big shapes, screen slope only of detail finer than the mesh (procedural-terrain.md) |
| Near terrain grain or 2-pixel-tall bars when skimming | Per-pixel lit octaves too fine for a slanted pixel's long side | Light per pixel only waves of ~20 px, faded by footprint / cos(view to ground) |
| Fine diagonal hatching on lit terrain | Smoothstep inside each texel of a baked noise texture (flat spots per texel) | Plain trilinear, and light per pixel only well-sampled octaves |
| Near relief "smooth" but suddenly busy when a constant changes | Area clamp in the screen-slope normal flattening close relief | Clamp far below the pixel area at the closest view |
| Valley fog fills deserts and canyons like cumulus | Fog from depth below average ground only | Gate by ground type from the map colour; thickness over the view's slant; wavy tops |
| Sea waves form arcs or rings round the camera | Isotropic wave noise; the sky reflection picks out slope along each line of sight | Stretch the crests along one axis (wind direction); long per-octave fade by pixel size (procedural-terrain.md) |
| Far sea turns to noise or static | Waves and sparkles still drawn where they're under a pixel | Fade them off from about 2 to 10 times the camera height; leave the far sea to the glint's roughness |
| Sun sparkles look like white dust over the sea | Fixed sparkle field, or a lobe much wider than the roughness | Two opposite-drifting fields multiplied; lobe ~1.6x roughness with its tail cut |
| Hard black blotches on the sea under cloud | Cloud cover cutting the sky reflection as well as the glint | Hide only the sun's glint under cloud |
| Far clumps look like rocks, mesas, pancakes or ice floes | An opaque height-field surface lit like ground: it can't thin out, let light in or glow at its edges | A thin volume after the first hit: a dozen samples over a short span from just before it, soft top and underside, over a separate deck ([gas-giant-clouds.md](gas-giant-clouds.md)) |
| Horizontal stair-step ribs on steep cloud walls (a storm's eye wall) | The crossing taken from the coarse step; a wall steeper than one step jumps across it | Bisect the last coarse step a few times, then interpolate linearly |
| A storm or swirl appears in one frame | A wide domain warp placed when the camera passes a height: every clump it touches changes at once | Fix it to the planet, set before the cloud shows |
| Near-black gaps between bright near heaps; a hard join to the paler far band | Deep shaded cloud inside the haze-free zone, with too little light through the cloud | More multiple scattering and sky light, a higher sky-light floor in shade. Floor light doesn't help. |
| Tall heaps pop in near the camera, or heap rims shift every few seconds | A baked window swapped without a fade, or re-baked a fraction of a texel off | Snap windows to the texel grid; fade a swap in over about 0.5 s |
| Horizontal hatching on far cloud seen from high up | Bilinear reads of a coarse baked level crease at every texel | Cubic B-spline read from four filtered taps |
| No cloud for seconds on a fast dive, or the dive stalls | Bakes paced for a slow camera, or every strip drawing the whole target | Fast pace for first and "urgent" bakes; check the scissor (webgpu-webgl2.md) |
| Fading fine billows turns dots into regular ribs | The billows were hiding layered steps in the field under them | Fix the underlying steps; don't fade the billows to hide speckle |
| A thin high cloud layer reads as flat decals or fly-through plates | A sheet has no depth; a thin volume seen edge-on at speed slices | Leave it out, or make it part of the main march's density |
| "Fur": grey hairy spikes or step-sliced cones over a far cloud band | Relief (Worley, a fine octave) in a height field that changes faster than the far march's steps; or a frame running ahead of its bake on a loaded GPU | Billows in lighting and normals only, or cells several steps wide; judge looks on an unloaded GPU ([gas-giant-clouds.md](gas-giant-clouds.md)) |
| Bright grey-white cloud on a gas giant's night side | Flat far lighting `dot(N, L) / L.y` is about 1 whatever the Sun's height | Multiply by the Sun's own fall-off (mu0) |
| The whole view turns to fog after a bake | Signed distances written to a target that clamps negatives read 0 | Store an offset value ([webgpu-webgl2.md](webgpu-webgl2.md)) |
| Every look compiles to a black frame after a small change | JS unary minus on a TSL node wrote NaN into the WGSL | `.negate()` or `.mul(-1)` |
| Stair-stepped haze edge at the horizon with sky colour showing through holes | Rays that slip through gaps in the near layer and miss the floor get no haze | Give missed rays the sky colour; haze both sides of a hand-over |
| Cloud missing in stills taken from a frozen pose | The first bake hadn't finished within the settle time | Log bake state with every still; seek a warm-up pose first |
| God rays flicker as the camera moves | The ray source twinkles, and the coarse gas cut shifts a little each frame | Keep the source steady; blend the rays over the last few frames, restarted on any cut or jump (nebula-fly-in.md) |
| Rays seem to come from an empty corner | The source star is fully hidden by the gas in front of it | Give its glare a small floor (about 0.12 of full) so the source always reads |
| A blob flashes on screen as the camera passes a cloud on the way in | The cloud is drawn at full strength while the path goes by it | Ease the cloud in only once the camera is past and looking away |
| A freeze of a second or more in a shot, with no shader compiles logged | Not always the shader: ours had about 10 ms of page work and was older than the new cloud | Check the build before the change; log page work, uploads and long tasks, not only compiles |
| Each visible filament sits in a dark halo of its own when rays are on | The rays are cut by the pixel's own gas | Use only nearby gas over a short screen distance as the blocker |
| The WebGL2 build never finishes loading (minutes) | A long ray-march shader with nested loops is too much for ANGLE on Direct3D | Time the WebGL2 compile in the lab before the app swap; pick a lighter look per backend |
| A volume is soft close up whatever the octaves, resolution or step count | The cloud takes longer to go opaque than its detail is deep: detail finer than that depth is fog | Raise opacity and firm the edge by pixel size at the sample; octaves that push the face in and out without thinning it ([cloud-layer-over-a-photo.md](cloud-layer-over-a-photo.md)) |
| Grain or "dust" on firm cloud close up | Long jittered steps land at random depths in opaque cloud | Walk long steps on the cheap shape, re-walk a step that finds near cloud in short ones |
| Holes or bitten-off cloud after adding refinement steps | Rays inside the layer spent every iteration on short steps and never reached their end | Give the short steps a budget; carry on in long steps after it |
| The ground under a cloud volume is a flat plain with a soft shadow | The deck is the map on a smooth sphere | Make the bottom of the volume a full sheet of cloud; light it by the Sun's height; weak self-shadow in the Sun steps |
| Speckle over a thick low cloud sheet from far off | Its own shadow at full strength under long steps: one sample lit, the next black | Count the sheet for a fraction in the Sun steps; light its thin top as sheet, not as heap |
| Cavities cut into a cloud sheet don't read as cavities | A floor only tens of km down, lit like the rest | Real holes through to a dark depth; darken the cloud toward them |
| Straight creases or polygon edges round thresholded holes or regions | A low-resolution noise texture, magnified and thresholded: its texels' facets | Read a finer baked field at a coarser scale; wobble the threshold with the fine shape |
| Combed, smeared streaks like motion blur after "adding wind" | A coordinate warp on all axes leans every cloud over | Trace back along a sideways flow that is the same at every height ([cloud-layer-over-a-photo.md](cloud-layer-over-a-photo.md)) |
| Zigzags or chevrons of toothpaste | A one-pass sideways warp draws its own pattern | Follow the flow in several short steps; rotate about vortex centres |
| Smooth smears where cloud is swept by a flow | The fine octaves were read through the flow too | Read fine octaves at the sample's own place |
| Dozens of thin concentric rings in a vortex, like tree rings | Too much twist (5 radians or more at the centre) | About 2.5 radians |
| A storm reads as a ring doughnut | An even wall, or a ridge with a cliff outside it | Wall height from the wound shape; a level top that slopes gently into the surrounding cloud |
| A pale or dark wedge with straight edges across wound cloud | Colour read from the map at the sample's place while the shapes follow a flow: a map edge, magnified, lies straight across them | Read the map where the flow brought the cloud from |
| A feature the far picture doesn't have (a dark eye) appears from nowhere at the hand-over | It is drawn at full strength at every distance | Fade its strength in by pixel size at the sample |
| Pale far picture turns dark or heavy at the hand-over | The close look's tones (dense cloud, dark bases, dark openings) don't match the photo's | Keep the photo's tones under a high Sun; ease to full contrast as the Sun gets low |
| A pop on a fast oblique dive that a slow descent doesn't show | The take-over band is narrow in height and falls inside a frame or two | Start the every-pixel fade far higher; test on the fastest, most oblique path |
| A dark band on the horizon part-way down an approach | The far globe kept showing late (to stay sharp) and is darker toward the horizon than the cloud that replaces it | Match globe and cloud at the horizon, or hand far pixels over earlier and accept the softness |
| An approach reads as head-on though the path is angled | The view is held on the subject all the way down | Look where the camera is going; keep the subject off-centre until it banks in |
| A lighting or weight change "did nothing" for rounds | A stored TSL weight read a `toVar()` after it was reassigned | Snapshot the weight with its own `toVar()` |
| Change "did nothing" | Wrong layer is the one drawing at that height, or a guard hid it | Tint layers flat colours to see which one draws |
