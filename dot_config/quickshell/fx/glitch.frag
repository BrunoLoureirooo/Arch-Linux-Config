#version 440
// Workspace-switch tear (spec 8; the render's `tear`, CSS .gx/.gg/.gl/.gb). One step of
// the effect over a captured screen: nine horizontal bands displaced sideways (some
// stretched, slipped, inverted or reduced to one channel), a red and a cyan ghost copy
// blended with `screen`, and corrupted blocks (inverted, a1, a2, or palette noise).
// Every random value comes from `seed`, so a step is reproducible. Lengths are in the
// render's em: 1 em = 1/120 of the screen width.
// Compiled into glitch.frag.qsb by:
//   /usr/lib/qt6/bin/qsb --qt6 -o glitch.frag.qsb glitch.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float amp;     // band displacement, em
    float ghost;   // ghost offset, em (0 = no ghosts)
    float seed;    // per step, 0..100
    float blocks;  // number of corrupted blocks, 0..10
    float width;   // pixels
    float height;  // pixels
    vec4 cutsA;    // band edges 1-4 (sorted, 0..1)
    vec4 cutsB;    // band edges 5-8
    vec4 a1;
    vec4 a2;
    vec4 fg;
    vec4 bg;
};

layout(binding = 1) uniform sampler2D source;

float rnd(float n) {
    return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453);
}

float rnd2(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.13) * 43758.5453);
}

// CSS invert(1) hue-rotate(180deg): lightness flips, hue stays.
vec3 invertKeepHue(vec3 c) {
    vec3 i = 1.0 - c;
    return clamp(vec3(dot(i, vec3(-0.574, 1.430, 0.144)),
                      dot(i, vec3(0.426, 0.430, 0.144)),
                      dot(i, vec3(0.426, 1.430, -0.856))), 0.0, 1.0);
}

vec3 tap(vec2 uv) {
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
        return bg.rgb;
    return texture(source, uv).rgb;
}

void main() {
    vec2 p = qt_TexCoord0;
    float emX = 1.0 / 120.0;
    float emY = width / 120.0 / height;

    // Band: how many edges lie above this row; its own top and bottom edge.
    float e[10] = float[10](0.0, cutsA.x, cutsA.y, cutsA.z, cutsA.w,
                            cutsB.x, cutsB.y, cutsB.z, cutsB.w, 1.0);
    int b = 0;
    for (int k = 1; k < 9; k++)
        if (p.y >= e[k])
            b = k;
    float lo = e[b];
    float hi = e[b + 1];

    vec3 col = tap(p);  // the undistorted base layer under the bands
    float n = float(b) * 7.0;
    bool on = rnd(n + 1.0) < 0.85;
    if (on) {
        float sm = rnd(n + 2.0) < 0.3 ? 1.0 + rnd(n + 3.0) * 0.1 * amp / 4.0 : 1.0;
        float slip = amp > 3.0 && rnd(n + 4.0) < 0.2 ? (rnd(n + 5.0) - 0.5) * 6.0 : 0.0;
        float dx = (rnd(n + 7.0) - 0.5) * 2.0 * amp;
        vec2 q = vec2(0.5 + (p.x - 0.5 - dx * emX) / sm, p.y - slip * emY);
        if (q.y >= lo && q.y < hi && q.x >= 0.0 && q.x <= 1.0) {
            col = texture(source, q).rgb;
            float v = rnd(n + 6.0);
            if (amp > 3.0) {
                if (v < 0.22)
                    col = invertKeepHue(col);
                else if (v < 0.36)
                    col = vec3(col.r, 0.0, 0.0);
                else if (v < 0.5)
                    col = vec3(0.0, col.g, col.b);
            }
        }
    }

    // Ghosts: the whole frame shifted left (red) and right (cyan), screen-blended.
    if (ghost > 0.0) {
        vec3 r = vec3(tap(p + vec2(ghost * emX, 0.0)).r, 0.0, 0.0);
        vec3 c = tap(p - vec2(ghost * emX, 0.0)) * vec3(0.0, 1.0, 1.0);
        col = 1.0 - (1.0 - col) * (1.0 - r);
        col = 1.0 - (1.0 - col) * (1.0 - c);
    }

    // Corrupted blocks; a later block covers an earlier one.
    for (int i = 0; i < 10; i++) {
        if (float(i) >= blocks)
            break;
        float m = 100.0 + float(i) * 9.0;
        float v = rnd(m + 2.0);
        bool bar = v > 0.62;
        float w = bar ? 40.0 + rnd(m + 3.0) * 60.0 : 8.0 + rnd(m) * 32.0;          // % of width
        float h = bar ? 0.8 + rnd(m + 4.0) * 1.8 : 1.4 + rnd(m + 1.0) * 4.2;       // em
        float x0 = rnd(m + 5.0) * (100.0 - w) / 100.0;
        float y0 = rnd(m + 6.0) * 0.92;
        if (p.x < x0 || p.x >= x0 + w / 100.0 || p.y < y0 || p.y >= y0 + h * emY)
            continue;
        if (v < 0.3) {
            col = 1.0 - col;
        } else if (v < 0.45) {
            col = a1.rgb;
        } else if (v < 0.62) {
            col = a2.rgb;
        } else {
            // 3 px cells of palette noise (a1, a2, fg, bg, bg).
            float k = floor(rnd2(floor(p * vec2(width, height) / 3.0) + float(i)) * 5.0);
            col = k < 1.0 ? a1.rgb : (k < 2.0 ? a2.rgb : (k < 3.0 ? fg.rgb : bg.rgb));
        }
    }

    fragColor = vec4(col, 1.0) * qt_Opacity;
}
