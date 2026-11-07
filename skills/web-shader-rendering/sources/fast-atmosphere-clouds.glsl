// Reference only: parts of Felix Westin's "Fast Atmosphere" Shadertoy
// (https://www.shadertoy.com/view/lcfSRl, 2024), copied 7 Nov 2026.
// Licence: MIT (notice below). Port ideas into TSL; keep this notice with any
// substantial copied portion.
//
// EXCEPTION: CloudShape() and the PARAMS_* values come from another Shadertoy
// (https://www.shadertoy.com/view/csSfRK) whose licence is unknown (Shadertoy
// default is CC BY-NC-SA). Do not copy it; write our own height profile.
//
// What is useful for Saturn/Jupiter high-altitude cloud:
//  1. Cloud() - 2D coverage field + height profile; finer layers CARVE the
//     edges with remap01 instead of adding bumps, so the big shapes (and a far
//     match to the planet map, if the map drives coverage) stay put as detail
//     fades in.
//  2. Lum() - cheap light: 4 steps to the Sun + 2 straight up for sky light,
//     single exp(-le)*HG(0.85) + soft multi exp(-le*0.05)*Rayleigh phase.
//  3. The march writes vec4(direct, ambient, alpha, weighted depth); the final
//     pass (ResolveClouds) applies Sun/sky colour and aerial-perspective haze
//     at that depth.
//
// Copyright (c) 2024 Felix Westin
//
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
// LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
// OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
// WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

// ---- From Common -------------------------------------------------------
#define CLOUD_COVERAGE 0.3
#define CLOUD_DENSITY 1.0
#define CLOUD_PLANE_BOT 3000.0
#define CLOUD_PLANE_TOP 5000.0
#define TEMPORAL_ACCUMULATION_CLOUDS 0.85

float PhaseR(float costh) { return (1.0+sq(costh))*0.06; }
float PhaseM(float costh, float g)
{
    g = min(g, 0.9381);
    float k = 1.55*g-0.55*sq(g)*g;
    float a = 1.0-sq(k);
    float b = 12.57*sq(1.0-k*costh);
    return a/b;
}

// ---- Buffer C (clouds) --------------------------------------------------
float Noise(vec2 x) { return textureLod(iChannel0, x * 0.002, 0.0).x; } // 2D noise texture

// [csSfRK - licence unknown, do not copy] CloudShape(x, y, shapeParams):
//   x = coverage value, y = 0..1 height in the layer; returns density with a
//   rounded top (pow(y, k)) and optional anvil. PARAMS_CUMULUS = vec2(0.4, 0.6).
#define SCALE 1000.0
#define OFFSET vec2(4.0, 8.0)

float remap01(float x, float a, float b) { return clamp((x - a) / (b - a), 0.0, 1.0); }
float Height(vec3 p) { return length(p - PLANET_CENTER) - PLANET_RADIUS; }

float Cloud(vec3 p)
{
    float y = (Height(p) - CLOUD_PLANE_BOT) / (CLOUD_PLANE_TOP - CLOUD_PLANE_BOT);
    const float scale = 1.0 / SCALE;
    float n = Noise(p.xz * scale + OFFSET + vec2(-0.2, 0.3) * iTime);  // coverage (map lum for us)
    float d = CloudShape(n - 1.0 + CLOUD_COVERAGE * 2.0, y, SHAPE);     // own profile needed
    float n2 = Noise(p.xz * scale * 8.0 - vec2(0.2, 0.0) * iTime);
    float n3 = Noise(p.xz * scale * 40.0 + vec2(1.0, 0.0) * iTime);
    d = remap01(d, (1.0 - n2) * 0.3, 1.0);   // carve: layer 2
    d = remap01(d, (1.0 - n3) * 0.1, 1.0);   // carve: layer 3
    d *= smoothstep(0.0, 0.75, y);
    return sq(d) * CLOUD_DENSITY;
}

vec3 Lum(vec3 p, vec3 ld, float costh, float ext, float dither)
{
    float le = 0.0, ae = 0.0;
    int sc = 4;
    float ss = (CLOUD_PLANE_TOP - CLOUD_PLANE_BOT) / float(sc);
    for (int j = 0; j < sc; j++) le += Cloud(p + ld * (float(j) + dither) * ss) * ss;      // to the Sun
    sc = 2;
    for (int j = 0; j < sc; j++) ae += Cloud(p + vec3(0, 1, 0) * (float(j) + dither) * ss) * ss; // up: sky light
    float single = exp(-le) * PhaseM(costh, 0.85);
    float multi = exp(-le * 0.05) * PhaseR(costh);
    multi *= 1.0 - exp(-ext * 6e2);
    return vec3(single + multi, (exp(-ae) + exp(-ae * 0.05)) * 0.5, 0);
}

// March (mainImage of Buffer C), core loop:
//   enter/exit from the two shell spheres (and ground); 64 steps, step 100 m
//   growing 5% per step, dithered start.
//   for (...) {
//       vec3 p = ro + rd * (t + ss * dither.x);
//       float h = Height(p); if (h < CLOUD_PLANE_BOT || h > CLOUD_PLANE_TOP) break;
//       float le = Cloud(p);
//       vec3 ll = le > 0.0 ? Lum(p, sunDir, costh, le, dither.y) : vec3(0);
//       float lt = exp(-le * ss);
//       float is = tsm * (1.0 - lt);
//       depth = mix(depth, t, sq(tsm));   // transmittance-weighted cloud depth
//       s += ll * is;
//       tsm *= lt;
//       if (tsm < 1e-5) break;
//       t += ss; ss *= 1.05; if (t > exit) break;
//   }
//   out = mix(vec4(s.xy / (1.0 - tsm), 1.0 - tsm, depth), prev, TEMPORAL_ACCUMULATION_CLOUDS);
//   // vec4(direct, ambient, alpha, weighted depth); prev = last frame (temporal blend)

// ---- Image (composite) --------------------------------------------------
vec4 ResolveClouds(vec4 clouds, vec3 ro, vec3 rd, Light light1, Light light2, float atmosphereOcclusion)
{
    float cloudDepth = clouds.w;
    float cloudAlpha = clamp(clouds.z + 1e-5, 0.0, 1.0);
    vec3 cloudPos = ro + rd * cloudDepth;
    float fogWeight = GetFogWeight(ro, rd, cloudDepth, cloudPos.y);
    vec4 transmittance;
    vec3 scattering = GetAtmosphere(ro, rd, cloudDepth, light1.direction, light1.radiance, transmittance, vec4(HEIGHT_FOG_COLOR, fogWeight), atmosphereOcclusion);
    vec3 al = GetAtmosphere(cloudPos, vec3(0, 1, 0), INFINITY, light1.direction, light1.radiance); // sky light at the cloud
    clouds.x *= sqrt(atmosphereOcclusion);
    vec3 cloudColor = (GetLightTransmittance(cloudPos, light1.direction) * light1.radiance * clouds.x + al * clouds.y * 2.0) * cloudAlpha;
    cloudColor = cloudColor * transmittance.xyz + scattering * cloudAlpha;  // haze at the cloud's depth
    return vec4(cloudColor, 1.0 - cloudAlpha);
}
// Composite: color = color * clouds.a + clouds.rgb;
// GetAtmosphere / GetLightTransmittance (analytic, Earth-tuned) are in the
// Common tab of the original (not copied here).
