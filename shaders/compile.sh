#!/bin/bash

files=$(find . -name "*.vert" -or -name "*.comp" -or -name "*.frag")

for file in $files; do
	outName="${file}.spv"
	glslangValidator -V $file -o $outName
done
