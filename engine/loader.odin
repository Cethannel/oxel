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

loadGltfMeshes :: proc(
	engine: ^VulkanEngine,
	filePath: string,
) -> (
	meshes: [dynamic]MeshAsset,
	ok: bool = true,
) {
	log.infof("Loading file: %s", filePath)

	cfilepath := strings.clone_to_cstring(filePath)
	defer delete_cstring(cfilepath)

	data, result := cgltf.parse_file({}, cfilepath)
	if result != .success {
		log.errorf("Failed to load glfw file (%s), got error: %s", filePath, result)
		ok = false
		return
	}
	result = cgltf.load_buffers({}, data, cfilepath)
	if result != .success {
		log.errorf("Failed to load glfw file (%s), got error: %s", filePath, result)
		ok = false
		return
	}

	gltf: cgltf.asset
	for mesh in data.meshes {
		newMesh: MeshAsset
		indices: [dynamic]u32
		vertices: [dynamic]ModelVertex

		newMesh.name = strings.clone_from_cstring_bounded(mesh.name, 1024)

		for p in mesh.primitives {
			newSurface: GeoSurface
			newSurface.startIndex = cast(u32)len(indices)
			newSurface.count = cast(u32)p.indices.count

			initial_vtx := len(vertices)

			{
				indices_len := len(indices)
				resize(&indices, cast(uint)indices_len + p.indices.count)

				out := cgltf.accessor_unpack_indices(
					p.indices,
					raw_data(indices[indices_len:]),
					size_of(u32),
					p.indices.count,
				)
			}

			{
				posAttrib, ok := findAttribute(p.attributes, "POSITION")
				if !ok {
					panic("Failed to get POSITION attrib")
				}

				assert(!posAttrib.data.is_sparse, "Pos is sparse")
				assert(posAttrib.data.stride == size_of(f32) * 3, "Size bad")

				vertices_len := len(vertices)
				resize(&vertices, cast(uint)vertices_len + posAttrib.data.count)

				for i: uint = 0; i < posAttrib.data.count; i += 1 {
					newvtx: ModelVertex
					fmt.assertf(
						cast(bool)cgltf.accessor_read_float(
							posAttrib.data,
							i,
							raw_data(newvtx.position[:]),
							3,
						),
						"Failed to access field: %d",
						i,
					)
					newvtx.normal = {1, 0, 0}
					newvtx.color = 1.
					newvtx.uv_x = 0
					newvtx.uv_y = 0
					vertices[initial_vtx + cast(int)i] = newvtx
				}
			}

			{
				normals, ok := findAttribute(p.attributes, "NORMAL")
				if ok {
					for i: uint = 0; i < normals.data.count; i += 1 {
						assert(
							cast(bool)cgltf.accessor_read_float(
								normals.data,
								i,
								raw_data(vertices[initial_vtx + cast(int)i].normal[:]),
								3,
							),
							"Failed to access field",
						)
					}
				}
			}

			{
				uvs, ok := findAttribute(p.attributes, "TEXCOORD_0")
				if ok {
					for i: uint = 0; i < uvs.data.count; i += 1 {
						v: [2]f32
						assert(
							cast(bool)cgltf.accessor_read_float(uvs.data, i, raw_data(v[:]), 2),
							"Failed to access field",
						)
						vertices[initial_vtx + cast(int)i].uv_x = v.x
						vertices[initial_vtx + cast(int)i].uv_y = v.y
					}
				}
			}

			{
				colors, ok := findAttribute(p.attributes, "COLOR_0")
				if ok {
					for i: uint = 0; i < colors.data.count; i += 1 {
						assert(
							cast(bool)cgltf.accessor_read_float(
								colors.data,
								i,
								raw_data(vertices[initial_vtx + cast(int)i].color[:]),
								4,
							),
							"Failed to access field",
						)
					}
				}
			}

			append(&newMesh.surfaces, newSurface)
		}

		OverrideColors :: true
		if (OverrideColors) {
			for &vtx in vertices {
				vtx.color.xyz = vtx.normal
				vtx.color.w = 1.0
			}
		}
		newMesh.meshBuffers =
			uploadMesh(engine, indices[:], vertices[:]) or_else panic("Failed to uploadMesh")

		log.info("Appending mesh")
		append(&meshes, newMesh)
	}

	log.info("Loaded gltf")

	return
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
