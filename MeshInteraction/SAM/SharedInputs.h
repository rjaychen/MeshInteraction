#ifndef SharedInputs_h
#define SharedInputs_h

#include <simd/simd.h>

typedef struct {
    simd_float3 mean;
    simd_float3 std;
    simd_uint2 size;
    simd_uint2 padding;
} PreprocessingInput ;

typedef struct {
    simd_float2 scaleSizeFactor;
} PostprocessingInput;

#endif
