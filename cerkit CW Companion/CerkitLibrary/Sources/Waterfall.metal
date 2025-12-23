#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float4 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Simple Quad Vertex Shader
vertex VertexOut waterfallVertex(uint vertexID [[vertex_id]],
                                 constant float4 *positions [[buffer(0)]],
                                 constant float2 *texCoords [[buffer(1)]]) {
    VertexOut out;
    out.position = positions[vertexID];
    out.texCoord = texCoords[vertexID];
    return out;
}

// Fragment Shader
fragment float4 waterfallFragment(VertexOut in [[stage_in]],
                                  texture2d<float> spectrumTexture [[texture(0)]],
                                  texture1d<float> colorMap [[texture(1)]],
                                  constant float &offset [[buffer(0)]],
                                  sampler textureSampler [[sampler(0)]]) {
    
    // Calculate scrolling coordinate
    // The texture is updated as a ring buffer. 'offset' points to the "newest" line.
    // We want 'v=0' (top) to be the newest line.
    // So we assume the latest data is written at 'offset'.
    // We want to sample from 'offset - v'.
    // Let's simplify:
    // v goes 0 (top) to 1 (bottom).
    // offset is the row index in UV space (0..1) where we just wrote.
    // We want to read from (offset - v). If negative, wrap around.
    
    float v = in.texCoord.y;
    float ringCoord = offset - v;
    if (ringCoord < 0.0) { ringCoord += 1.0; }
    
    // Default Orientation: Frequency = X, Time = Y (Vertical Scroll)
    float u = in.texCoord.x;
    
    // Revert Rotation: float2(u, ringCoord)
    float magnitude = spectrumTexture.sample(textureSampler, float2(u, ringCoord)).r;
    
    magnitude = saturate(magnitude);
    
    // Map to Color
    float4 color = colorMap.sample(textureSampler, magnitude);
    
    return color;
}
