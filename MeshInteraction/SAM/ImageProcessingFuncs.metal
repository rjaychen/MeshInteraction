#include <metal_stdlib>
#include "SharedInputs.h"

using namespace metal;

constexpr sampler linear_sampler = sampler(filter::linear);

kernel void preprocessing_kernel(texture2d<float, access::sample> texture [[ texture(0) ]],
                                 constant PreprocessingInput& input [[ buffer(0) ]],
                                 device float* rBuffer [[ buffer(1) ]],
                                 device float* gBuffer [[ buffer(2) ]],
                                 device float* bBuffer [[ buffer(3) ]],
                                 uint2 xy [[ thread_position_in_grid ]]) {
    
    if (xy.x >= input.size.x || xy.y >= input.size.y) return;
    
    const float2 uv = float2(xy) / float2(input.size);
    float2 final_uv = uv;
    if (input.size.x > input.size.y) {
        final_uv = float2(uv.x + float(input.padding.y)/float(input.size.x), uv.y); // correct uv position.
    }
    float4 color = texture.sample(linear_sampler, final_uv);
    color.rgb = (color.rgb - input.mean) / input.std; // normalize color into 0-1 range
    
    const int index = xy.y * (input.size.x + input.padding.x) + xy.x + input.padding.y; // downsize image with aspect ratio
    
    rBuffer[index] = color.r;
    gBuffer[index] = color.g;
    bBuffer[index] = color.b;
    
}

kernel void postprocessing_kernel(texture2d<float, access::sample> mask [[ texture(0) ]],
                                  texture2d<float, access::read> output_read [[ texture(1) ]],
                                  texture2d<float, access::write> output [[ texture(2) ]],
                                  constant PostprocessingInput& input [[ buffer(0) ]],
                                  uint2 xy [[ thread_position_in_grid ]]) {
    if (xy.x >= output_read.get_width() || xy.y >= output_read.get_height()) return;
    
    const float2 uv = float2(xy) / float2(output_read.get_width(), output_read.get_height());
    const float2 mask_uv = uv * input.scaleSizeFactor;
    const float4 mask_value = 1.0 - clamp(mask.sample(linear_sampler, mask_uv), float4(0), float4(1));
    
    output.write(mask_value, xy);
}
