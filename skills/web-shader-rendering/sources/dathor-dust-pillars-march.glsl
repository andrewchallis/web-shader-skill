// Reference only: the ray-march and shading parts of the "Buffer A" tab of
// "Where James Webb Cannot Reach" by dathor / Nullpunkt42
// (https://www.shadertoy.com/view/7XyXRV, 2 Nov 2026), copied on
// 5 Nov 2026. Licence and credits as in dathor-dust-pillars-volume.glsl
// ("Free for anyone to use"; Hoskins hashes MIT).
// Left out here: the gas backdrop, the star layers and mainImage (camera,
// dither, compositing).
//
// Worth studying: adaptive steps (big in empty space, thin fixed "shell"
// steps near the surface), three-tap light visibility along the Sun
// direction, rim glow from exp(-|sd| * k) at the surface, smoke floor lit
// by the difference towards the light, and fog/shaft terms added per step.

const int   MAX_STEPS = 150;
const float NEAR      = .05;
const float FAR       = 6.5;

const float PERIOD = 6.;
const float YMIN   = -1.3;
const float YMAX   =  1.5;

const float DUST_DENSITY = 10.;
const float RIM_GAIN     = 7.;
const float HALO_GAIN    = 2.5;
const float SHAFT_GAIN   = .12;
const float FOG          = .20;
const float PINK_GAIN    = 12.;
const vec3  HAZE_COL     = vec3(.01, .06, .12);
const vec3  SHAFT_COL    = vec3(1.0, .80, .45);

const float SMOKE_TOP    = -.25;
const float SMOKE_BOT    = -1.0;
const float SMOKE_GAIN   = 2.5;
const float SMOKE_ABSORB = 2.5;

const float FOG_SHIFT = .02;
const float FOG_GLOW  = .25;
const float FOG_TINT  = .5;

const float GRAD_EPS         = .03;
const float SHELL_STEP_NEAR  = .012;
const float SHELL_STEP_FAR   = .020;
const float START_JITTER     = .14;

const vec3 L3 = vec3(.400, .781, .480);

float hash31(vec3 p)
{
    vec3 p3 = fract(p * .1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

float noise3(vec3 p)
{
    vec3 ip = floor(p);
    vec3 f  = fract(p);
    f = f * f * (3. - 2. * f);
    float n000 = hash31(ip);
    float n100 = hash31(ip + vec3(1,0,0));
    float n010 = hash31(ip + vec3(0,1,0));
    float n110 = hash31(ip + vec3(1,1,0));
    float n001 = hash31(ip + vec3(0,0,1));
    float n101 = hash31(ip + vec3(1,0,1));
    float n011 = hash31(ip + vec3(0,1,1));
    float n111 = hash31(ip + vec3(1,1,1));
    return mix( mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
                mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z );
}

float erosion(vec3 p)
{
    vec3 q = p * vec3(5.5, 2.2, 5.5);
    return .65 * noise3(q) + .35 * noise3(q * 2.03 + 7.1);
}


float sdfAt(vec3 p)
{
    float lowMask = smoothstep(.2, -1., p.y);
    p.xz += .035 * lowMask * vec2(sin(p.z * 1.7 + p.y * 2. + iTime * .25),
                                  cos(p.x * 1.3 + p.y * 2. + iTime * .20));

    vec3  uvw  = vec3(p.x / PERIOD, (p.y - YMIN) / (YMAX - YMIN), p.z / PERIOD);
    float over = 0.;
    if (uvw.y > 1.) over = (uvw.y - 1.) * (YMAX - YMIN);
    if (uvw.y < 0.) over = uvw.y * (YMAX - YMIN);
    uvw.y  = clamp(uvw.y, 0., 1.);
    uvw.xz = fract(uvw.xz);
    return texture(iChannel0, uvw).r + over;
}

vec3 gradAt(vec3 p)
{
    const vec2  k = vec2(1., -1.);
    const float e = GRAD_EPS;
    return normalize( k.xyy * sdfAt(p + k.xyy * e)
                    + k.yyx * sdfAt(p + k.yyx * e)
                    + k.yxy * sdfAt(p + k.yxy * e)
                    + k.xxx * sdfAt(p + k.xxx * e) + 1e-6 );
}

float lightVisibility(vec3 p, float jit)
{
    float j = 1. + .4 * jit;
    float v = 1.;
    v = min(v, smoothstep(-.02, .12, sdfAt(p + L3 * .12 * j)));
    v = min(v, smoothstep(-.02, .20, sdfAt(p + L3 * .35 * j)));
    v = min(v, smoothstep(-.02, .30, sdfAt(p + L3 * .80 * j)));
    return v;
}

float smokeAt(vec3 p, float sd)
{
    vec3 uvw = vec3(p.x / PERIOD, (p.y - YMIN) / (YMAX - YMIN), p.z / PERIOD);
    vec3 a = vec3(fract(uvw.x * 2.3 + iTime * .004),
                  clamp(uvw.y, 0., 1.),
                  fract(uvw.z * 2.3 + iTime * .003));
    float n = texture(iChannel0, a).r;

    float ripple = .5 + .5 * sin(n * 9. + iTime * .12);

    float fill = exp(-max(sd, 0.) * 1.6);
    float h    = smoothstep(SMOKE_TOP + (ripple - .5) * .5, SMOKE_BOT, p.y);
    return h * fill * (.35 + .65 * smoothstep(.3, .8, ripple));
}


vec3 fogPalette(float x)
{
    const vec3 teal = vec3(.08, .45, .40);
    const vec3 gold = vec3(.95, .62, .22);
    const vec3 pink = vec3(1.0, .25, .50);
    const vec3 blue = vec3(.10, .30, .70);
    x = fract(x) * 4.;
    vec3 c = mix(teal, gold, smoothstep(0., 1., x));
    c = mix(c, pink, smoothstep(1., 2., x));
    c = mix(c, blue, smoothstep(2., 3., x));
    return mix(c, teal, smoothstep(3., 4., x));
}

vec3 dustShade(vec3 p, vec3 N, vec3 rd, float sd, float vis)
{
    float warmth = smoothstep(.2, -.9, p.y);
    vec3  alb    = mix(vec3(.06, .10, .22), vec3(.32, .11, .04), warmth);

    float nl   = dot(N, L3);
    float dif  = max(nl, 0.) * vis;
    float wrap = .5 + .5 * nl; wrap *= wrap;
    float ao   = mix(.35, 1., clamp(sdfAt(p + N * .06) / .06, 0., 1.));
    vec3  amb  = mix(vec3(.02, .04, .08), vec3(.10, .17, .28), .5 + .5 * N.y);

    vec3  H    = normalize(L3 - rd);
    float spec = pow(max(dot(N, H), 0.), 40.) * vis;
    float fre  = pow(1. - max(dot(N, -rd), 0.), 3.);
    float tr   = pow(max(dot(rd, L3), 0.), 3.) * exp(sd * 20.);

    vec3 c = alb * (vec3(1., .85, .6) * (dif * .9 + wrap * .25) + amb * 2.) * ao;
    c += vec3(.95, .75, .35) * spec * .3 * ao;
    c += vec3(.20, .45, .50) * fre * (.3 + dif) * .5 * ao;
    c += vec3(1., .62, .25) * tr * ao;
    return c;
}

vec4 marchDust(vec3 ro, vec3 rd, float dither, out float hitT)
{
    hitT = 1e9;
    const vec3 gold    = vec3(.95, .78, .28);
    const vec3 hotGold = vec3(1.00, .93, .62);
    const vec3 halo    = vec3(.20, .62, .50);
    const vec3 warm    = vec3(.90, .50, .15);
    const vec3 pink    = vec3(1.00, .22, .50);

    float phase = .35 + 2.0 * pow(max(dot(rd, L3), 0.), 6.);

    vec3  col = vec3(0.);
    float T   = 1.;
    float t   = NEAR + dither * START_JITTER;

    for (int i = 0; i < MAX_STEPS; i++)
    {
        if (t > FAR || T < .02) break;

        vec3  p  = ro + rd * t;
        float sd = sdfAt(p);

        float dl  = (sd > .15) ? clamp(sd * .5, .04, .14)
                                : mix(SHELL_STEP_NEAR, SHELL_STEP_FAR, smoothstep(0., 1.5, t));
        float fog = exp(-t * FOG);

        float vis = lightVisibility(p, dither);

        vec3 fc = fogPalette(iTime * FOG_SHIFT + p.x * .07 + p.z * .05 + p.y * .2);

        if (sd > 0.)
            col += SHAFT_COL * vis * phase * SHAFT_GAIN * .12 * dl * T * fog;

        col += mix(HAZE_COL, fc * .14, FOG_TINT) * FOG * dl * T;

        if (sd > 0. && p.y < SMOKE_TOP + .2)
        {
            float sm = smokeAt(p, sd);
            if (sm > .001)
            {
                vec3  pl  = p + L3 * .2;
                float sl  = smokeAt(pl, sdfAt(pl));
                float lit = clamp(.35 + 2. * (sm - sl), 0., 1.) * (.4 + .6 * vis);
                vec3  sc  = mix(vec3(.05, .07, .14), fc * .75, lit)
                          + fc * FOG_GLOW * (.4 + .6 * lit);

                col += T * fog * sc * sm * SMOKE_GAIN * dl;
                T   *= exp(-sm * SMOKE_ABSORB * dl);
            }
        }

        if (sd < .18)
        {
            vec3  N   = gradAt(p);
            float lit = smoothstep(0., .95, dot(N, L3)) * (.3 + .7 * vis);
            float er  = erosion(p);

            float outside = max(sd, 0.);
            float seaMask = 1. - .85 * smoothstep(-.30, -.60, p.y);
            float rim     = exp(-abs(sd) * 45.) * lit * (.5 + .8 * er * er) * seaMask;

            vec3 glow  = (gold * rim * 1.1 + hotGold * rim * rim * .5) * RIM_GAIN;
            glow      += (halo * exp(-outside * 9.) * lit * (.4 + er) * .10
                        + warm * exp(-outside * 4.) * lit * .03) * HALO_GAIN * seaMask;

            float head = smoothstep(.10, .70, p.y) * smoothstep(.35, .85, N.y)
                       * exp(-abs(sd) * 35.) * (.4 + er);
            glow += pink * head * PINK_GAIN;

            float a      = smoothstep(.015, -.035, sd);
            vec3  dustCol = dustShade(p, N, rd, sd, vis);

            col += T * fog * (dustCol * a * DUST_DENSITY + glow * (1. - a)) * dl;
            T   *= exp(-a * DUST_DENSITY * dl);
            if (hitT > 1e8 && T < .5) hitT = t;
        }

        t += dl;
    }
    return vec4(col, T);
}

vec3 aces(vec3 x)
{
    return clamp((x * (2.51 * x + .03)) / (x * (2.43 * x + .59) + .14), 0., 1.);
}
