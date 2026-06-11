#include <metal_stdlib>
using namespace metal;

// ============================================================================
//  BreathOS background shader
//
//  Entry point: breathBackground (SwiftUI .colorEffect).
//  Uniforms: time, phase, prevPhase, progress, transition, resolution.
//  Phases:  0 = inhale (flash)   1 = hold-in (slow fractal)
//           2 = exhale (fractal) 3 = hold-out (edge→center vignette)
//
//  All math is float; FBM is computed inline (no textures); <= 5 octaves.
// ============================================================================

// ----- value noise -----------------------------------------------------------

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);          // smoothstep interpolation
    float a = hash21(i + float2(0.0, 0.0));
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float value = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    for (int i = 0; i < 5; i++) {                // 5 octaves
        value += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return value;
}

// Domain-warped fractal field — "flowing" texture. Returns ~0..1.
static float warpedField(float2 uv, float t) {
    float2 p = uv * 3.0;
    float2 q = float2(fbm(p + float2(0.0, 0.0) + t * 0.10),
                      fbm(p + float2(5.2, 1.3) + t * 0.12));
    float2 r = float2(fbm(p + 3.5 * q + float2(1.7, 9.2) + t * 0.08),
                      fbm(p + 3.5 * q + float2(8.3, 2.8) + t * 0.06));
    return fbm(p + 3.5 * r);
}

// ----- palettes / per-phase renderers ---------------------------------------

// Blue palette: deep blue-teal -> #4DB3F2 light blue.
static float3 bluePalette(float f) {
    float3 deep  = float3(0.024, 0.176, 0.318);
    float3 light = float3(0.302, 0.702, 0.949);   // #4DB3F2
    return mix(deep, light, clamp(f, 0.0, 1.0));
}

// Exhale / hold-in: flowing blue fractal. `driftScale` slows the drift for hold-in.
static float3 renderFractal(float2 fuv, float t, float driftScale) {
    float f = warpedField(fuv, t * driftScale);
    f = smoothstep(0.15, 0.95, f);
    return bluePalette(f);
}

// Inhale (recovery): sharp bright flash from the center, radius grows over the
// first ~30% of the phase, then holds. `cn` is normalized so 1.0 = screen corner.
static float3 renderFlash(float2 cn, float progress) {
    float dist = length(cn);
    float maxR = 1.05;
    float radius = max(mix(0.0, maxR, smoothstep(0.0, 0.3, progress)), 0.0001);
    float bright = 1.0 - smoothstep(radius * 0.15, radius, dist);
    float3 base  = float3(0.02, 0.03, 0.05);
    float3 flash = float3(1.0, 0.99, 0.96);
    return mix(base, flash, clamp(bright, 0.0, 1.0));
}

// Hold-out: black procedural waves close in from all sides over the continuing
// fractal. The wavy boundary is FBM-modulated and advected toward the center;
// darkening is visible immediately at progress 0 (thin churning rim) and leaves
// only a small lit spot in the middle at progress 1.
static float3 renderHoldOut(float2 fuv, float2 cn, float t, float progress) {
    // Same drift speed as the exhale fractal -> seamless, instant phase entry.
    float3 base = renderFractal(fuv, t, 1.0);

    float dist = length(cn);
    float2 dir = cn / max(dist, 1e-3);
    // Sampling point slides outward along the radial direction, so the dark
    // pattern appears to crawl inward from every edge.
    float n = fbm(cn * 3.5 + dir * t * 0.45);
    float wave = (n - 0.5) * 0.35;

    float lightR = mix(1.02, 0.06, clamp(progress, 0.0, 1.0)); // light radius shrinks
    float light = 1.0 - smoothstep(lightR - 0.22 + wave, lightR + wave, dist);
    return base * clamp(light, 0.0, 1.0);
}

static float3 renderPhase(int phase, float2 fuv, float2 cn, float t, float progress) {
    if (phase == 0)      return renderFlash(cn, progress);            // recovery inhale
    else if (phase == 2) return renderFractal(fuv, t, 1.0);           // exhale / breath series
    else if (phase == 1) return renderFractal(fuv, t, 0.2);           // hold-in (slow drift)
    else                 return renderHoldOut(fuv, cn, t, progress);  // hold-out (black waves)
}

// ----- entry point -----------------------------------------------------------

[[ stitchable ]]
half4 breathBackground(float2 pos, half4 color,
                       float time, float phase, float prevPhase,
                       float progress, float transition,
                       float2 resolution) {
    float2 uv = pos / resolution;
    float aspect = resolution.x / max(resolution.y, 1.0);
    float2 fuv = float2(uv.x * aspect, uv.y);               // aspect-correct field coords
    float2 c   = float2((uv.x - 0.5) * aspect, uv.y - 0.5); // centered radial coords
    // Normalize so length(cn) == 1.0 exactly at the screen corners — radial
    // effects (flash, closing waves) then span the visible screen 0...1.
    float2 cn  = c / max(length(float2(0.5 * aspect, 0.5)), 1e-3);

    int curP = int(phase + 0.5);
    int prvP = int(prevPhase + 0.5);

    float3 col;
    if (transition < 0.999) {
        // Crossfade from the previous phase (frozen at its end) into the current one.
        float3 a = renderPhase(prvP, fuv, cn, time, 1.0);
        float3 b = renderPhase(curP, fuv, cn, time, progress);
        col = mix(a, b, clamp(transition, 0.0, 1.0));
    } else {
        col = renderPhase(curP, fuv, cn, time, progress);
    }

    return half4(half3(col), 1.0h);
}
