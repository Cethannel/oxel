package engine

import "core:fmt"
import "core:log"
import "core:strings"
import "vendor:cgltf"

GeoSurface :: struct {
	startIndex: u32,
	count:      u32,
}

MeshAsset :: struct {
	name:        string,
	surfaces:    [dynamic]GeoSurface,
	meshBuffers: GPUMeshBuffers,
}

@(private)
findAttribute :: proc(
	attributes: []cgltf.attribute,
	name: cstring,
) -> (
	attrib: ^cgltf.attribute = nil,
	ok: bool = false,
) {
	log.infof("Finding: %s", name)
	for &a in attributes {
		log.infof("Checking: %s", a.name)
		if name == a.name {
			ok = true
			attrib = &a
			return
		}
	}

	return
}
