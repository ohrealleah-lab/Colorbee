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

// Layer pixels are stored with straight alpha; premultiply here for blending.
fragment float4 layer_fragment(QuadOut in [[stage_in]],
                               texture2d<float> layer [[texture(0)]],
                               sampler layerSampler [[sampler(0)]],
                               constant QuadUniforms &u [[buffer(0)]]) {
    float4 color = layer.sample(layerSampler, in.uv);
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
