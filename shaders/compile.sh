#!/bin/bash

find . \( -name "*.vert" -o -name "*.comp" -o -name "*.frag" \) -print0 |
parallel -0 \
    --eta \
    --progress \
    glslangValidator -V {} -o {}.spv
