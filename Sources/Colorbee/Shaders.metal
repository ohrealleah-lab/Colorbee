#include <metal_stdlib>
using namespace metal;

// Must match QuadUniforms in Renderer.swift.
struct QuadUniforms {
    float4 rect;          // x, y, width, height in drawable pixels, top-left origin
    float2 viewportSize;  // drawable size in pixels
    float opacity;
    float checkerSize;    // checkerboard cell size in drawable pixels
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

// Layer pixels are stored with straight alpha; premultiply here for blending.
fragment float4 layer_fragment(QuadOut in [[stage_in]],
                               texture2d<float> layer [[texture(0)]],
                               sampler layerSampler [[sampler(0)]],
                               constant QuadUniforms &u [[buffer(0)]]) {
    float4 color = layer.sample(layerSampler, in.uv);
    float alpha = color.a * u.opacity;
    return float4(color.rgb * alpha, alpha);
}

fragment float4 checker_fragment(QuadOut in [[stage_in]], constant QuadUniforms &u [[buffer(0)]]) {
    float2 cell = floor(in.position.xy / u.checkerSize);
    float shade = fmod(cell.x + cell.y, 2.0) < 1.0 ? 1.0 : 0.85;
    return float4(shade, shade, shade, 1);
}
