#include <metal_stdlib>
using namespace metal;

struct VertexOut { float4 position [[position]]; float2 uv; };
struct Uniforms {
    float openness;
    float fullAngle;
    float2 resolution;
    float strength;
    float eyeHeight;
    float eyeDistance;
    float padding;
};

vertex VertexOut foldVertex(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    return { float4(p * 2.0 - 1.0, 0, 1), float2(p.x, 1.0 - p.y) };
}

fragment float4 foldFragment(VertexOut in [[stage_in]],
                              array<texture2d<float>, 6> desktop [[texture(0)]],
                              constant Uniforms &u [[buffer(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float fold = 1.0 - clamp(u.openness, 0.0, 1.0);
    float angle = fold * (u.fullAngle - 45.0) * M_PI_F / 180.0;

    // Anchor the observer in keyboard/world coordinates. Its horizontal
    // sight line meets the desktop's top at the calibrated maximum angle.
    // Convert that fixed world point to the original screen-plane basis.
    float full = u.fullAngle * M_PI_F / 180.0;
    float eyeY = u.eyeDistance * cos(full) + u.eyeHeight * sin(full);
    float eyeZ = u.eyeDistance * sin(full) - u.eyeHeight * cos(full);
    // Ray intersection with the original plane. The top is allowed to fall
    // inside the physical screen; never rescale that bounded image to fit.
    float h = 1.0 - in.uv.y;
    float3 panelPoint = float3(in.uv.x - 0.5, h * cos(angle), h * sin(angle));
    float depth = eyeZ / (eyeZ - panelPoint.z);
    float2 original = float2(panelPoint.x * depth,
                            eyeY + (panelPoint.y - eyeY) * depth);
    float2 uv = float2(original.x + 0.5, 1.0 - original.y);

    // Six actual Gaussian-filtered source images, not a mipmap blur. The
    // radius is tied to source coordinates so it stays on the virtual plane.
    constexpr float sigma[6] = { 0.0, 2.0, 5.0, 12.0, 28.0, 64.0 };
    float motion = smoothstep(0.0, 1.0, fold);
    float edge = clamp(original.y, 0.0, 1.0);
    float radius = min(64.0, 64.0 * motion * pow(edge, 1.15) * u.strength);
    float3 color = float3(0);
    for (uint i = 0; i < 5; ++i) {
        if (radius >= sigma[i] && radius <= sigma[i + 1]) {
            float mixAmount = smoothstep(sigma[i], sigma[i + 1], radius);
            color = mix(desktop[i].sample(s, uv).rgb,
                        desktop[i + 1].sample(s, uv).rgb, mixAmount);
            break;
        }
    }
    // Let blurred content and its silhouette disappear into black together.
    float2 spread = max(0.5 / u.resolution,
                        float2(radius * u.resolution.y / 1000.0) / u.resolution * 1.7);
    float2 coverage = smoothstep(-spread, spread, uv)
                    * (1.0 - smoothstep(1.0 - spread, 1.0 + spread, uv));
    float shade = 1.0 - 0.82 * motion * pow(edge, 1.6);
    // The animation's closed endpoint is 45 degrees, not the physical latch.
    float visibility = smoothstep(0.0, 0.22, u.openness);
    return float4(color * coverage.x * coverage.y * shade * visibility, 1.0);
}
