#include <metal_stdlib>
using namespace metal;

// Must match QuadUniforms in Renderer.swift.
struct QuadUniforms {
    float4 rect;          // x, y, width, height in drawable pixels, top-left origin
    float4 keyColor;      // Transparent Selection color (straight RGB)
    float2 viewportSize;  // drawable size in pixels
    float2 imageSize;     // image pixels covered by the quad
    float opacity;
    float checkerSize;    // checkerboard cell size in drawable pixels
    float keyEnabled;
    float antsPhase;
    float pixelSize;      // drawable pixels per image pixel
    float blendMode;      // BlendMode.rawValue
    float4 adjustParams;  // the adjustment's settings (see Renderer.adjustmentUniforms)
    float adjustKind;     // 0 none, 1 invert, 2 desaturate, 3 brightness/contrast, 4 hue/saturation, 5 blur, 6 sharpen
    float4 photoParams;   // Adjust Photo: how many vignettes (x) and grains (z), in buffer 1; Texture (y, -1...1)
    float smooth;         // 1 when layers are sampled smoothly (zoomed out, or a stretched selection)
    float4 detailParams;  // Adjust Photo (DetailAmounts): color noise, luminance and color detail scales, halo damping
    float4 detailParams2; // fine boost, Masking's threshold, 1 to show the Masking mask
    float clipWarnings;   // the composite's clipping warnings: 1 highlights, 2 shadows, 3 both
};

struct QuadOut {
    float4 position [[position]];
    float2 uv;
};

vertex QuadOut quad_vertex(uint vid [[vertex_id]], constant QuadUniforms &u [[buffer(0)]]) {
    const float2 corners[4] = { {0, 0}, {1, 0}, {0, 1}, {1, 1} };
    float2 corner = corners[vid];
    float2 pixel = u.rect.xy + corner * u.rect.zw;
    QuadOut out;
    out.position = float4(pixel.x / u.viewportSize.x * 2 - 1, 1 - pixel.y / u.viewportSize.y * 2, 0, 1);
    out.uv = corner;
    return out;
}

// A line segment: rect holds the two end points (x0, y0, x1, y1) in drawable pixels, pixelSize its width.
vertex QuadOut line_vertex(uint vid [[vertex_id]], constant QuadUniforms &u [[buffer(0)]]) {
    float2 a = u.rect.xy, b = u.rect.zw;
    float2 direction = length(b - a) > 0 ? normalize(b - a) : float2(1, 0);
    float2 normal = float2(-direction.y, direction.x) * (u.pixelSize / 2);
    const float2 corners[4] = { {0, -1}, {1, -1}, {0, 1}, {1, 1} };
    float2 corner = corners[vid];
    float2 pixel = mix(a, b, corner.x) + normal * corner.y;
    QuadOut out;
    out.position = float4(pixel.x / u.viewportSize.x * 2 - 1, 1 - pixel.y / u.viewportSize.y * 2, 0, 1);
    out.uv = corner;
    return out;
}

// Layer pixels are stored with straight alpha. Smooth sampling mixes them premultiplied, so the color
// kept in fully transparent pixels can't bleed into the edges as a fringe (review F, finding 3).
// Returns straight alpha, like a plain sample.
static float4 sampleLayer(texture2d<float> layer, sampler layerSampler, float2 uv, float smooth) {
    if (smooth < 0.5) return layer.sample(layerSampler, uv);
    float2 size = float2(layer.get_width(), layer.get_height());
    float2 position = uv * size - 0.5;
    float2 f = fract(position);
    int2 base = int2(floor(position));
    int2 last = int2(size) - 1;
    float4 taps[4];
    const int2 offsets[4] = { {0, 0}, {1, 0}, {0, 1}, {1, 1} };
    for (int i = 0; i < 4; i++) {
        float4 texel = layer.read(uint2(clamp(base + offsets[i], int2(0), last)));
        taps[i] = float4(texel.rgb * texel.a, texel.a);
    }
    float4 mixed = mix(mix(taps[0], taps[1], f.x), mix(taps[2], taps[3], f.x), f.y);
    return mixed.a > 0 ? float4(mixed.rgb / mixed.a, mixed.a) : float4(0);
}

// Layer pixels are stored with straight alpha; premultiply here for blending.
fragment float4 layer_fragment(QuadOut in [[stage_in]],
                               texture2d<float> layer [[texture(0)]],
                               sampler layerSampler [[sampler(0)]],
                               constant QuadUniforms &u [[buffer(0)]]) {
    float4 color = sampleLayer(layer, layerSampler, in.uv, u.smooth);
    if (u.keyEnabled > 0.5 && color.a > 0 && all(abs(color.rgb - u.keyColor.rgb) < 0.5 / 255.0)) {
        discard_fragment();
    }
    float alpha = color.a * u.opacity;
    return float4(color.rgb * alpha, alpha);
}

// A flat color (keyColor), for handles.
fragment float4 solid_fragment(QuadOut in [[stage_in]], constant QuadUniforms &u [[buffer(0)]]) {
    return float4(u.keyColor.rgb * u.keyColor.a, u.keyColor.a);
}

// A flat-colored disc filling the quad, for round handles.
fragment float4 disc_fragment(QuadOut in [[stage_in]], constant QuadUniforms &u [[buffer(0)]]) {
    if (length(in.uv - 0.5) > 0.5) discard_fragment();
    return float4(u.keyColor.rgb * u.keyColor.a, u.keyColor.a);
}

// A soft shadow around the canvas, so its edge shows on the gray around it (Leah, 2026-10-15). adjustParams holds
// the canvas rect (x, y, width, height) in drawable pixels, photoParams.x the shadow's reach, keyColor.a its strength.
fragment float4 shadow_fragment(QuadOut in [[stage_in]], constant QuadUniforms &u [[buffer(0)]]) {
    float2 halfSize = u.adjustParams.zw / 2;
    float2 outside = max(abs(in.position.xy - (u.adjustParams.xy + halfSize)) - halfSize, 0.0);
    float fade = 1 - saturate(length(outside) / u.photoParams.x);
    float alpha = u.keyColor.a * fade * fade;
    return float4(0, 0, 0, alpha);
}

fragment float4 checker_fragment(QuadOut in [[stage_in]], constant QuadUniforms &u [[buffer(0)]]) {
    float2 cell = floor(in.position.xy / u.checkerSize);
    float shade = fmod(cell.x + cell.y, 2.0) < 1.0 ? 1.0 : 0.85;
    return float4(shade, shade, shade, 1);
}

// Marching ants: selected pixels with an unselected neighbor one screen pixel away.
fragment float4 ants_fragment(QuadOut in [[stage_in]],
                              texture2d<float> mask [[texture(0)]],
                              sampler maskSampler [[sampler(0)]],
                              constant QuadUniforms &u [[buffer(0)]]) {
    float2 uv = in.uv;
    if (mask.sample(maskSampler, uv).r < 0.5) discard_fragment();
    float2 dx = dfdx(uv);
    float2 dy = dfdy(uv);
    float neighbors = min(min(mask.sample(maskSampler, uv + dx).r, mask.sample(maskSampler, uv - dx).r),
                          min(mask.sample(maskSampler, uv + dy).r, mask.sample(maskSampler, uv - dy).r));
    if (neighbors >= 0.5) discard_fragment();
    float dash = floor((in.position.x + in.position.y) / 8.0 + u.antsPhase);
    float shade = fmod(dash, 2.0) < 1.0 ? 0.0 : 1.0;
    return float4(shade, shade, shade, 1);
}

// Edit ▸ Feather…'s preview: a red tint over what isn't selected, fading in across a soft edge. The quad covers the
// canvas; adjustParams is the mask's rect in image pixels.
fragment float4 tint_fragment(QuadOut in [[stage_in]],
                              texture2d<float> mask [[texture(0)]],
                              sampler maskSampler [[sampler(0)]],
                              constant QuadUniforms &u [[buffer(0)]]) {
    float2 maskUV = (in.uv * u.imageSize - u.adjustParams.xy) / u.adjustParams.zw;
    float selected = (all(maskUV >= 0.0) && all(maskUV <= 1.0)) ? mask.sample(maskSampler, maskUV).r : 0.0;
    float alpha = 0.45 * (1.0 - selected);
    return float4(0.9 * alpha, 0.15 * alpha, 0.2 * alpha, alpha);
}

// Pixel grid: one drawable pixel along each image pixel's top and left edge, in whichever of
// black or white contrasts with what's underneath.
fragment float4 grid_fragment(QuadOut in [[stage_in]],
                              float4 destination [[color(0)]],
                              constant QuadUniforms &u [[buffer(0)]]) {
    float2 offset = fract(in.uv * u.imageSize) * u.pixelSize;
    if (offset.x >= 1.0 && offset.y >= 1.0) discard_fragment();
    float luminance = dot(destination.rgb, float3(0.299, 0.587, 0.114));
    float3 lineColor = luminance > 0.5 ? float3(0.0) : float3(1.0);
    return float4(mix(destination.rgb, lineColor, 0.5), destination.a);
}

// MARK: Blend modes. Must match BlendMode.swift (W3C Compositing and Blending), case for case.

static float lum(float3 c) { return dot(c, float3(0.3, 0.59, 0.11)); }

static float3 clipColor(float3 c) {
    float l = lum(c), n = min(c.r, min(c.g, c.b)), x = max(c.r, max(c.g, c.b));
    if (n < 0) c = l + (c - l) * l / (l - n);
    if (x > 1) c = l + (c - l) * (1 - l) / (x - l);
    return c;
}

static float3 setLum(float3 c, float l) { return clipColor(c + (l - lum(c))); }
static float sat(float3 c) { return max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b)); }

static float3 setSat(float3 c, float s) {
    float low = min(c.r, min(c.g, c.b)), high = max(c.r, max(c.g, c.b));
    if (high <= low) return float3(0);
    return (c - low) * (s / (high - low));
}

static float colorDodge(float b, float s) { return b == 0 ? 0 : (s >= 1 ? 1 : min(1.0, b / (1 - s))); }
static float colorBurn(float b, float s) { return b >= 1 ? 1 : (s <= 0 ? 0 : 1 - min(1.0, (1 - b) / s)); }
static float hardLight(float b, float s) { return s <= 0.5 ? b * 2 * s : b + (2 * s - 1) - b * (2 * s - 1); }
static float softLight(float b, float s) {
    if (s <= 0.5) return b - (1 - 2 * s) * b * (1 - b);
    float d = b <= 0.25 ? ((16 * b - 12) * b + 4) * b : sqrt(b);
    return b + (2 * s - 1) * (d - b);
}

static float3 blendColor(int mode, float3 b, float3 s) {
    switch (mode) {
    case 1: return min(b, s);                                                        // darken
    case 2: return b * s;                                                            // multiply
    case 3: return float3(colorBurn(b.r, s.r), colorBurn(b.g, s.g), colorBurn(b.b, s.b));
    case 4: return max(b, s);                                                        // lighten
    case 5: return b + s - b * s;                                                    // screen
    case 6: return float3(colorDodge(b.r, s.r), colorDodge(b.g, s.g), colorDodge(b.b, s.b));
    case 7: return min(b + s, float3(1));                                            // additive
    case 8: return float3(hardLight(s.r, b.r), hardLight(s.g, b.g), hardLight(s.b, b.b)); // overlay
    case 9: return float3(softLight(b.r, s.r), softLight(b.g, s.g), softLight(b.b, s.b));
    case 10: return float3(hardLight(b.r, s.r), hardLight(b.g, s.g), hardLight(b.b, s.b));
    case 11: return abs(b - s);                                                      // difference
    case 12: return b + s - 2 * b * s;                                               // exclusion
    case 13: return setLum(setSat(s, sat(b)), lum(b));                               // hue
    case 14: return setLum(setSat(b, sat(s)), lum(b));                               // saturation
    case 15: return setLum(s, lum(b));                                               // color
    case 16: return setLum(b, lum(s));                                               // luminosity
    default: return s;                                                               // normal
    }
}

// A straight color at `sourceAlpha`, blended in `mode` onto the premultiplied backdrop (Compositing.blend).
static float4 blendOnto(float4 backdrop, float3 color, float sourceAlpha, int mode) {
    float backdropAlpha = backdrop.a;
    float3 blended = color;
    if (mode != 0 && backdropAlpha > 0) {
        float3 b = backdrop.rgb / backdropAlpha;
        blended = (1 - backdropAlpha) * color + backdropAlpha * blendColor(mode, b, color);
    }
    return float4(sourceAlpha * blended + (1 - sourceAlpha) * backdrop.rgb, sourceAlpha + backdropAlpha * (1 - sourceAlpha));
}

// Composites a straight-alpha layer onto the premultiplied layers already drawn beneath it, read
// straight from the render target (Apple GPUs allow this without a second texture).
fragment float4 blend_layer_fragment(QuadOut in [[stage_in]],
                                     texture2d<float> layer [[texture(0)]],
                                     sampler layerSampler [[sampler(0)]],
                                     constant QuadUniforms &u [[buffer(0)]],
                                     float4 backdrop [[color(0)]]) {
    float4 color = sampleLayer(layer, layerSampler, in.uv, u.smooth);
    // A selection floating over a layer that locks its transparency, already placed on its patch of that layer,
    // replaces what's under it (review U, finding 3).
    if (u.blendMode < -0.5) return float4(color.rgb * color.a, color.a);
    if (u.keyEnabled > 0.5 && color.a > 0 && all(abs(color.rgb - u.keyColor.rgb) < 0.5 / 255.0)) {
        discard_fragment();
    }
    float sourceAlpha = color.a * u.opacity;
    if (sourceAlpha <= 0) discard_fragment();
    return blendOnto(backdrop, color.rgb, sourceAlpha, int(u.blendMode + 0.5));
}

// A layer with its floating selection or pending shape already drawn in (premultiplied, at the drawable's
// pixels), blended at the layer's mode and opacity, as it will look once placed (review F, finding 1).
fragment float4 blend_isolated_fragment(QuadOut in [[stage_in]],
                                        texture2d<float> isolated [[texture(0)]],
                                        constant QuadUniforms &u [[buffer(0)]],
                                        float4 backdrop [[color(0)]]) {
    float4 premultiplied = isolated.read(uint2(in.position.xy));
    if (premultiplied.a <= 0) discard_fragment();
    return blendOnto(backdrop, premultiplied.rgb / premultiplied.a, premultiplied.a * u.opacity, int(u.blendMode + 0.5));
}

// The composited layers, already premultiplied, drawn 1:1 over the checkerboard.
fragment float4 composite_fragment(QuadOut in [[stage_in]],
                                   texture2d<float> layers [[texture(0)]],
                                   sampler layerSampler [[sampler(0)]],
                                   constant QuadUniforms &u [[buffer(0)]]) {
    float4 c = layers.sample(layerSampler, in.uv);
    // Adjust Photo's clipping warnings, on screen only: blown highlights (any channel at white) red, crushed
    // shadows (every channel at black) blue.
    int warnings = int(u.clipWarnings + 0.5);
    if (warnings > 0 && c.a > 0.004) {
        float3 straight = c.rgb / c.a;
        if ((warnings & 1) && max(straight.r, max(straight.g, straight.b)) >= 254.5 / 255) return float4(1, 0.1, 0.1, 1) * c.a;
        if ((warnings & 2) && max(straight.r, max(straight.g, straight.b)) <= 0.5 / 255) return float4(0.1, 0.35, 1, 1) * c.a;
    }
    return c;
}

// MARK: Adjustment layers. Must match Effect.pointwise and Compositing.adjust in ColorbeeCore.

static float3 hueSaturation(float3 c, float shift, float saturationChange, float lightnessChange) {
    float high = max(c.r, max(c.g, c.b)), low = min(c.r, min(c.g, c.b));
    float lightness = (high + low) / 2, chroma = high - low;
    float hue = 0, saturation = 0;
    if (chroma > 0) {
        saturation = chroma / (1 - abs(2 * lightness - 1));
        if (high == c.r) hue = 60 * fmod((c.g - c.b) / chroma, 6.0);
        else if (high == c.g) hue = 60 * ((c.b - c.r) / chroma + 2);
        else hue = 60 * ((c.r - c.g) / chroma + 4);
        if (hue < 0) hue += 360;
    }
    hue = fmod(hue + shift, 360.0);
    if (hue < 0) hue += 360;
    float s = saturationChange / 100, l = lightnessChange / 100;
    saturation = s >= 0 ? saturation + (1 - saturation) * s : saturation * (1 + s);
    lightness = l >= 0 ? lightness + (1 - lightness) * l : lightness * (1 + l);
    float outChroma = (1 - abs(2 * lightness - 1)) * saturation;
    float section = hue / 60;
    float second = outChroma * (1 - abs(fmod(section, 2.0) - 1));
    float3 rgb = section < 1 ? float3(outChroma, second, 0)
               : section < 2 ? float3(second, outChroma, 0)
               : section < 3 ? float3(0, outChroma, second)
               : section < 4 ? float3(0, second, outChroma)
               : section < 5 ? float3(second, 0, outChroma)
               : float3(outChroma, 0, second);
    return clamp(rgb + (lightness - outChroma / 2), 0.0, 1.0);
}

static float3 pointAdjustment(int kind, float4 p, float3 c) {
    switch (kind) {
    case 1: return 1 - c;
    case 2: return float3(dot(c, float3(0.2126, 0.7152, 0.0722)));
    case 3: return clamp(((c * 255 - 128) * (1 + p.y / 100) + 128 + p.x * 2.55) / 255, 0.0, 1.0);
    case 4: return hueSaturation(c, p.x, p.y, p.z);
    default: return c;
    }
}

// The adjusted color mixed by the blend mode and faded in by opacity, as Compositing.adjust does.
static float4 fadeIn(float4 backdrop, float3 adjusted, float adjustedAlpha, constant QuadUniforms &u) {
    int mode = int(u.blendMode + 0.5);
    float3 color = adjusted;
    if (mode != 0 && backdrop.a > 0) color = blendColor(mode, backdrop.rgb / backdrop.a, adjusted);
    float4 goal = float4(color * adjustedAlpha, adjustedAlpha);
    return backdrop + (goal - backdrop) * u.opacity;
}

// Invert, Desaturate, Brightness/Contrast and Hue/Saturation: each pixel on its own.
fragment float4 adjust_point_fragment(QuadOut in [[stage_in]],
                                      constant QuadUniforms &u [[buffer(0)]],
                                      float4 backdrop [[color(0)]]) {
    if (backdrop.a <= 0) return backdrop;
    float3 straight = backdrop.rgb / backdrop.a;
    return fadeIn(backdrop, pointAdjustment(int(u.adjustKind + 0.5), u.adjustParams, straight), backdrop.a, u);
}

// Color adjustments through a 3D table made from the same per-pixel function exports use (ColorLookup).
// adjustParams.x is the table's size; coordinates land on texel centers so the ends are exact.
fragment float4 adjust_lookup_fragment(QuadOut in [[stage_in]],
                                       texture3d<float> lookup [[texture(0)]],
                                       constant QuadUniforms &u [[buffer(0)]],
                                       float4 backdrop [[color(0)]]) {
    constexpr sampler tableSampler(filter::linear, address::clamp_to_edge);
    if (backdrop.a <= 0) return backdrop;
    float3 straight = clamp(backdrop.rgb / backdrop.a, 0.0, 1.0);
    float size = u.adjustParams.x;
    float3 adjusted = lookup.sample(tableSampler, (straight * (size - 1) + 0.5) / size).rgb;
    return fadeIn(backdrop, adjusted, backdrop.a, u);
}

// Levels, Curves and Posterize: one entry per 8-bit value for each channel (ChannelTable), read without
// interpolation, so the screen shows the same hard steps the export has.
fragment float4 adjust_channel_fragment(QuadOut in [[stage_in]],
                                        texture2d<float> table [[texture(0)]],
                                        constant QuadUniforms &u [[buffer(0)]],
                                        float4 backdrop [[color(0)]]) {
    if (backdrop.a <= 0) return backdrop;
    uint3 index = uint3(rint(clamp(backdrop.rgb / backdrop.a, 0.0, 1.0) * 255.0));
    float3 adjusted = float3(table.read(uint2(index.r, 0)).r, table.read(uint2(index.g, 0)).g, table.read(uint2(index.b, 0)).b);
    return fadeIn(backdrop, adjusted, backdrop.a, u);
}

// Adjust Photo (PhotoAdjustments in ColorbeeCore): detail from blurred copies of what's below, then the color
// table, then the vignettes (the filter's, then the panel's own). adjustParams: table size, sharpness, definition,
// noise reduction (0...1); detailParams and detailParams2 the rest of DetailAmounts. PhotoAdjustments.detail does the
// same on the CPU.
// Vignette.strength(x:y:in:shape:) over the canvas, at `position` in image pixels. shape: amount, midpoint, roundness,
// feather.
static float vignette_strength(float2 position, float2 size, float4 shape) {
    float2 halfSize = size / 2;
    float2 d = position - halfSize;
    float roundness = shape.z, distance;
    if (roundness > 0) {
        float k = min(roundness, 100.0) / 100, shortSide = min(halfSize.x, halfSize.y);
        distance = length(d / (halfSize + (shortSide - halfSize) * k)) / sqrt(2.0);
    } else if (roundness < 0) {
        float p = 2 + min(-roundness, 100.0) / 100 * 6;
        float2 n = max(abs(d / halfSize), 1e-6);
        distance = pow(pow(n.x, p) + pow(n.y, p), 1 / p) / pow(2.0, 1 / p);
    } else {
        distance = length(d / halfSize) / sqrt(2.0);
    }
    float start = clamp(shape.y, 0.0, 100.0) / 100 * 0.95;
    float width = (1 - start) * clamp(shape.w, 0.0, 100.0) / 50;
    if (width <= 0) return distance > start ? 1 : 0;
    float t = clamp((distance - start) / width, 0.0, 1.0);
    return t * t * (3 - 2 * t);
}

// Grain.hash, Grain.valueNoise and Grain.offset: the same grain at the same image pixel as on the CPU.
static uint grain_hash(int x, int y, uint seed) {
    uint h = uint(x) * 0x8DA6B343u ^ uint(y) * 0xD8163841u ^ seed * 0xCB1AB31Fu;
    h ^= h >> 16;
    h *= 0x7FEB352Du;
    h ^= h >> 15;
    h *= 0x846CA68Bu;
    h ^= h >> 16;
    return h;
}

static float grain_corner(int x, int y, uint seed) {
    return float(grain_hash(x, y, seed)) / 4294967295.0 * 2 - 1;
}

static float grain_noise(float2 p, float cell, uint seed) {
    float2 g = p / cell - 0.5;
    float2 i = floor(g), f = g - i;
    float2 s = f * f * (3 - 2 * f);
    int ix = int(i.x), iy = int(i.y);
    float top = grain_corner(ix, iy, seed) + (grain_corner(ix + 1, iy, seed) - grain_corner(ix, iy, seed)) * s.x;
    float bottom = grain_corner(ix, iy + 1, seed) + (grain_corner(ix + 1, iy + 1, seed) - grain_corner(ix, iy + 1, seed)) * s.x;
    return top + (bottom - top) * s.y;
}

// grain: amount, size, roughness.
static float grain_offset(int2 pixel, float3 grain) {
    float cell = 1 + clamp(grain.y, 0.0, 100.0) / 100 * 3;
    float k = clamp(grain.z, 0.0, 100.0) / 100;
    float2 p = float2(pixel) + 0.5;
    float even = grain_noise(p, cell, 1u);
    float rough = k > 0 ? grain_noise(p, max(1.0, cell / 2), 2u) : 0;
    return (even * (1 - k) + rough * k) * clamp(grain.x, 0.0, 100.0) / 100 * 0.2;
}

static float3 unblurred(texture2d<float> blurred, texture2d<float> coverage, uint2 pixel, float3 fallback) {
    float4 soft = blurred.read(pixel);
    float weight = coverage.read(pixel).r;
    if (weight > 0.001) soft /= weight;
    return soft.a > 0 ? clamp(soft.rgb / soft.a, 0.0, 1.0) : fallback;
}

fragment float4 adjust_photo_fragment(QuadOut in [[stage_in]],
                                      texture3d<float> lookup [[texture(0)]],
                                      texture2d<float> fine [[texture(1)]],
                                      texture2d<float> fineCoverage [[texture(2)]],
                                      texture2d<float> wide [[texture(3)]],
                                      texture2d<float> wideCoverage [[texture(4)]],
                                      texture2d<float> medium [[texture(5)]],
                                      texture2d<float> mediumCoverage [[texture(6)]],
                                      texture2d<float> sharp [[texture(7)]],
                                      texture2d<float> sharpCoverage [[texture(8)]],
                                      constant QuadUniforms &u [[buffer(0)]],
                                      constant float4 *effects [[buffer(1)]],
                                      float4 backdrop [[color(0)]]) {
    constexpr sampler tableSampler(filter::linear, address::clamp_to_edge);
    if (backdrop.a <= 0) return backdrop;
    float3 c = clamp(backdrop.rgb / backdrop.a, 0.0, 1.0);
    float sharpness = u.adjustParams.y, definition = u.adjustParams.z, noiseReduction = u.adjustParams.w;
    float textureAmount = u.photoParams.y, colorNoise = u.detailParams.x;
    float haloDamping = u.detailParams.w, fineBoost = u.detailParams2.x, maskThreshold = u.detailParams2.y;
    bool showsMask = u.detailParams2.z > 0.5;
    if (sharpness > 0 || definition > 0 || noiseReduction > 0 || textureAmount != 0 || colorNoise > 0 || showsMask) {
        uint2 pixel = uint2(in.position.xy);
        float3 original = c;
        float3 soft = noiseReduction > 0 ? unblurred(fine, fineCoverage, pixel, original) : original;
        float3 sharpBlur = sharpness > 0 ? unblurred(sharp, sharpCoverage, pixel, original) : original;
        float3 wider = definition > 0 ? unblurred(wide, wideCoverage, pixel, original) : original;
        bool needsMedium = textureAmount != 0 || colorNoise > 0 || maskThreshold > 0;
        float3 middle = needsMedium ? unblurred(medium, mediumCoverage, pixel, original) : original;
        float3 fromMiddle = abs(original - middle);
        float mask = maskThreshold > 0 ? smoothstep(maskThreshold * 0.5, maskThreshold * 1.5, max(fromMiddle.r, max(fromMiddle.g, fromMiddle.b))) : 1;
        if (showsMask) return fadeIn(backdrop, float3(mask), backdrop.a, u);
        if (noiseReduction > 0) {
            float3 difference = abs(original - soft);
            float s = u.detailParams.y;
            float weight = noiseReduction * (1 - smoothstep(0.04 * s, 0.2 * s, max(difference.r, max(difference.g, difference.b))));
            c += (soft - c) * weight;
        }
        if (colorNoise > 0) {
            const float3 lumaWeights = float3(0.2126, 0.7152, 0.0722);
            float3 chroma = c - dot(c, lumaWeights), around = middle - dot(middle, lumaWeights);
            float3 difference = abs(chroma - around);
            float s = u.detailParams.z;
            float weight = colorNoise * (1 - smoothstep(0.08 * s, 0.3 * s, max(difference.r, max(difference.g, difference.b))));
            c += (around - chroma) * weight;
        }
        if (sharpness > 0) {
            float3 difference = original - sharpBlur;
            float size = max(abs(difference.r), max(abs(difference.g), abs(difference.b)));
            float gain = 1;
            if (haloDamping > 0) gain = 1 / (1 + size * haloDamping);
            if (fineBoost > 0) gain = 1 + fineBoost * (1 - smoothstep(0.0, 0.1, size));
            gain *= mask;
            c += difference * sharpness * 1.5 * gain;
        }
        if (definition > 0) c += (original - wider) * definition * 0.6;
        if (textureAmount != 0) c += (original - middle) * textureAmount * 0.8;
        c = clamp(c, 0.0, 1.0);
    }
    float size = u.adjustParams.x;
    c = lookup.sample(tableSampler, (c * (size - 1) + 0.5) / size).rgb;
    // The vignettes, then the grains: the filter's, then the panel's own, as in Effects.photoAdjusted.
    int vignetteCount = int(u.photoParams.x + 0.5), grainCount = int(u.photoParams.z + 0.5);
    float2 position = in.uv * u.imageSize;
    for (int i = 0; i < vignetteCount; i++) {
        float strength = vignette_strength(position, u.imageSize, effects[i]) * effects[i].x / 100;
        c = strength >= 0 ? c * (1 - strength) : c + (1 - c) * -strength;
    }
    if (grainCount > 0) {
        int2 pixel = int2(clamp(floor(position), float2(0), u.imageSize - 1));
        for (int i = 0; i < grainCount; i++) {
            c = clamp(c + grain_offset(pixel, effects[vignetteCount + i].xyz), 0.0, 1.0);
        }
    }
    return fadeIn(backdrop, c, backdrop.a, u);
}

// Blur and Sharpen read a blurred copy of the layers beneath, made on the GPU. Dividing by the blurred
// canvas coverage keeps the image's edges from fading into the transparent area around it.
fragment float4 adjust_blur_fragment(QuadOut in [[stage_in]],
                                     texture2d<float> blurred [[texture(0)]],
                                     texture2d<float> coverage [[texture(1)]],
                                     constant QuadUniforms &u [[buffer(0)]],
                                     float4 backdrop [[color(0)]]) {
    uint2 pixel = uint2(in.position.xy);
    float4 soft = blurred.read(pixel);
    float weight = coverage.read(pixel).r;
    if (weight > 0.001) soft /= weight;
    if (int(u.adjustKind + 0.5) == 5) {
        if (soft.a <= 0) return backdrop + (float4(0) - backdrop) * u.opacity;
        return fadeIn(backdrop, clamp(soft.rgb / soft.a, 0.0, 1.0), min(soft.a, 1.0), u);
    }
    if (backdrop.a <= 0) return backdrop;
    float3 original = backdrop.rgb / backdrop.a;
    float3 softColor = soft.a > 0 ? soft.rgb / soft.a : original;
    float3 sharp = clamp(original + u.adjustParams.x / 100 * (original - softColor), 0.0, 1.0);
    return fadeIn(backdrop, sharp, backdrop.a, u);
}
