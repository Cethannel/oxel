#!/bin/sh bash

slangc chunk.slang -profile glsl_450 -target spirv -o chunk.spv \
    -entry vertexMain -stage vertex \
    -entry fragmentMain -stage fragment \
    -capability GL_EXT_buffer_reference+GL_EXT_shader_explicit_arithmetic_types

slangc gradient_color.slang -profile glsl_450 -target spirv -o gradient_color.spv \
    -entry main -stage compute

slangc sky.slang -profile glsl_450 -target spirv -o sky.spv \
    -entry main -stage compute
