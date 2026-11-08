// Reference only: the "Volume A" tab (baked SDF) of "Where James Webb Cannot
// Reach" by dathor / Nullpunkt42 (https://www.shadertoy.com/view/7XyXRV,
// 2 Nov 2026), copied 5 Nov 2026.
// Licence: Inspired by FabriceNeyret2's "Volumetric Perlin to exact
// SDF" (https://www.shadertoy.com/view/NXGSRK). The hashes are Dave Hoskins'
// "Hash without Sine" (MIT). Credit all three when porting.
//
// Idea: bake the shape once into a periodic 3D texture: rounded leaning
// columns on jittered cells, unioned with a turbulent floor, both domain
// warped and worn by abs-Perlin turbulence near their surface.

const float PERIOD = 6.;
const float YMIN   = -1.3;
const float YMAX   =  1.5;

const float FLOOR_Y        = -.70;
const float PILLAR_SKIP    = .30;
const vec2  HERO           = vec2(1.5, .5);
const float HERO_TOP       = 1.15;
const float CLEAR_RADIUS   = 2.9;
const float CORRIDOR_CELLS = 3.;
const float TURB_FREQ      = 1.5;
const float TURB_AMP       = .90;
const vec3  HASH_SEED      = vec3(467., 581., 389.);


float hash21(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

float hash31(vec3 p)
{
    vec3 p3 = fract(p * .1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}


float cornerHash(vec3 c, float period)
{
    c.xz = mod(c.xz, period);
    return hash31(c);
}

float valueNoise(vec3 p, float period)
{
    vec3 ip = floor(p);
    vec3 f  = fract(p);
    f = f * f * (3. - 2. * f);

    float n000 = cornerHash(ip + vec3(0,0,0), period);
    float n100 = cornerHash(ip + vec3(1,0,0), period);
    float n010 = cornerHash(ip + vec3(0,1,0), period);
    float n110 = cornerHash(ip + vec3(1,1,0), period);
    float n001 = cornerHash(ip + vec3(0,0,1), period);
    float n101 = cornerHash(ip + vec3(1,0,1), period);
    float n011 = cornerHash(ip + vec3(0,1,1), period);
    float n111 = cornerHash(ip + vec3(1,1,1), period);

    return mix( mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
                mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z );
}

float fbm3(vec3 p, float period, int octaves)
{
    float v = 0.;
    float a = .5;
    for (int i = 0; i < 6; i++)
    {
        if (i >= octaves) break;
        v += a * valueNoise(p, period);
        p = p * 2. + vec3(17.3, 9.1, 5.7);
        period *= 2.;
        a *= .5;
    }
    return v;
}


vec3 gradientAt(vec3 cell, float period)
{
    cell.xz = mod(cell.xz, period);
    mat3 seeds = mat3(HASH_SEED, 73. - HASH_SEED, HASH_SEED.zxy);
    return 2. * fract(sin(cell * seeds) * 3758.54) - 1.;
}

float cornerValue(vec3 x, vec3 cell, vec3 offset, float period)
{
    vec3 corner = cell + offset;
    return dot(gradientAt(corner, period), x - corner);
}

float perlinAbs(vec3 x, float period)
{
    vec3 cell = floor(x);
    vec3 w    = smoothstep(0., 1., fract(x));

    float n000 = cornerValue(x, cell, vec3(0,0,0), period);
    float n100 = cornerValue(x, cell, vec3(1,0,0), period);
    float n010 = cornerValue(x, cell, vec3(0,1,0), period);
    float n110 = cornerValue(x, cell, vec3(1,1,0), period);
    float n001 = cornerValue(x, cell, vec3(0,0,1), period);
    float n101 = cornerValue(x, cell, vec3(1,0,1), period);
    float n011 = cornerValue(x, cell, vec3(0,1,1), period);
    float n111 = cornerValue(x, cell, vec3(1,1,1), period);

    float nx00 = mix(n000, n100, w.x);
    float nx10 = mix(n010, n110, w.x);
    float nx01 = mix(n001, n101, w.x);
    float nx11 = mix(n011, n111, w.x);

    float nxy0 = mix(nx00, nx10, w.y);
    float nxy1 = mix(nx01, nx11, w.y);

    return 2. * abs(mix(nxy0, nxy1, w.z));
}

float turbulence(vec3 x, float period, int octaves)
{
    float sum = 0.;
    float scale = 1.;
    for (int i = 0; i < 6; i++)
    {
        if (i >= octaves) break;
        sum    += perlinAbs(x, period) / scale;
        x      *= 2.;
        period *= 2.;
        scale  *= 2.;
    }
    return sum;
}


float pillarSD(vec3 p)
{
    vec2  ip   = floor(p.xz);
    float best = 1e3;

    for (int j = -1; j <= 1; j++)
    {
        for (int i = -1; i <= 1; i++)
        {
            vec2 c  = ip + vec2(float(i), float(j));
            vec2 cm = mod(c, PERIOD);

            bool isHero = (cm == floor(HERO));
            if (!isHero)
            {
                if (cm.x < CORRIDOR_CELLS) continue;
                vec2 dv = abs(mod(c + .5 - HERO + .5 * PERIOD, PERIOD) - .5 * PERIOD);
                if (length(dv) < CLEAR_RADIUS) continue;
                if (hash21(cm) < PILLAR_SKIP) continue;
            }

            vec2  hh   = hash22(cm + 3.3);
            vec2  ctr  = isHero ? c + .5 : c + .5 + (hh - .5) * .7;
            float ytop = isHero ? HERO_TOP : .15 + 1.15 * hash21(cm + 1.7);

            float s = p.y - ytop;
            vec2 lean = isHero ? vec2(.14, -.07) : (vec2(hash21(cm + 8.1), hash21(cm + 9.7)) - .5) * .5;
            vec2 bend = isHero ? vec2(.10, .06) : (hh - .5) * .25;
            vec2 cc   = ctr + lean * s + bend * s * s;

            float w0    = isHero ? .30 : .26 + .18 * hash21(cm + 5.5);
            float flare = smoothstep(-.1, -1.5, s);
            float wy    = w0 * (.80 + .60 * flare);
            if (isHero) wy *= 1. + .20 * sin(s * 4.2 + 6.2831 * hash21(cm + 2.2));

            float rc = .6 * wy;
            vec2  q  = vec2(length(p.xz - cc) - wy + rc, s + rc);
            float d  = length(max(q, 0.)) + min(max(q.x, q.y), 0.) - rc;

            best = min(best, d);
        }
    }
    return best;
}


float bake(vec3 p, int octaves)
{
    vec3 w    = vec3(fbm3(p,                       PERIOD, 3),
                     fbm3(p + vec3(5.2, 1.3, 8.1), PERIOD, 3),
                     fbm3(p + vec3(2.7, 9.4, 3.3), PERIOD, 3));
    vec3 pw   = p + (w - .5) * vec3(.45, .20, .45);

    float n = turbulence(pw * TURB_FREQ + vec3(3., 7., 1.), PERIOD * TURB_FREQ, octaves) / 2. - .274;

    float pd      = pillarSD(pw);
    float pillars = pd + TURB_AMP * n * smoothstep(-.35, .02, pd);
    float sea     = (pw.y - FLOOR_Y) + .6 * n;

    return min(pillars, sea);
}


void mainVolume(out vec4 O, vec3 V)
{
    if (iFrame < 1)
    {
        vec3 res = vec3(textureSize(iChannel0, 0));
        vec3 u   = V / res;
        vec3 p   = vec3(u.x * PERIOD, mix(YMIN, YMAX, u.y), u.z * PERIOD);

        int octaves = (res.x >= 200.) ? 6 : 5;
        O = vec4(clamp(bake(p, octaves), -.6, 1.2), 0., 0., 0.);
    }
    else
    {
        O = texelFetch(iChannel0, ivec3(V), 0);
    }
}
