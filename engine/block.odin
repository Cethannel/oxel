package engine

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:log"
import "core:math/linalg"
import "core:strings"
// packed_pos = (x & 0xF) | ((y & 0xFF) << 4) | ((z & 0xF) << 12)
// model_index = vertex index into baseVertices (for UV/normal/color lookup)
baseChunkVertices := [?]ChunkVertex {
	// Front face (z=0): verts 0-3
	{packed_pos = 0, model_index = 0}, // (0,0,0)
	{packed_pos = 0, model_index = 1}, // (1,0,0)
	{packed_pos = 0, model_index = 2}, // (1,1,0)
	{packed_pos = 0, model_index = 3}, // (0,1,0)
	// Back face (z=1): verts 4-7
	{packed_pos = 0, model_index = 4}, // (0,0,1)
	{packed_pos = 0, model_index = 5}, // (1,0,1)
	{packed_pos = 0, model_index = 6}, // (1,1,1)
	{packed_pos = 0, model_index = 7}, // (0,1,1)
	// Left face (x=0): verts 8-11
	{packed_pos = 0, model_index = 8}, // (0,0,0)
	{packed_pos = 0, model_index = 9}, // (0,1,0)
	{packed_pos = 0, model_index = 10}, // (0,1,1)
	{packed_pos = 0, model_index = 11}, // (0,0,1)
	// Right face (x=1): verts 12-15
	{packed_pos = 0, model_index = 12}, // (1,0,0)
	{packed_pos = 0, model_index = 13}, // (1,1,0)
	{packed_pos = 0, model_index = 14}, // (1,1,1)
	{packed_pos = 0, model_index = 15}, // (1,0,1)
	// Bottom face (y=0): verts 16-19
	{packed_pos = 0, model_index = 16}, // (0,0,0)
	{packed_pos = 0, model_index = 17}, // (0,0,1)
	{packed_pos = 0, model_index = 18}, // (1,0,1)
	{packed_pos = 0, model_index = 19}, // (1,0,0)
	// Top face (y=1): verts 20-23
	{packed_pos = 0, model_index = 20}, // (0,1,0)
	{packed_pos = 0, model_index = 21}, // (0,1,1)
	{packed_pos = 0, model_index = 22}, // (1,1,1)
	{packed_pos = 0, model_index = 23}, // (1,1,0)
}

Face :: enum {
	NegZ = 0,
	PosZ,
	NegX,
	PosX,
	NegY,
	PosY,
}

modelVertices := [?]ModelVertex {
	{
		position = {0.0, 0.0, 0.0},
		uv_x = 0,
		uv_y = 1,
		normal = {0.0, 0.0, -1.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {1.0, 0.0, 0.0},
		uv_x = 1,
		uv_y = 1,
		normal = {0.0, 0.0, -1.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {1.0, 1.0, 0.0},
		uv_x = 1,
		uv_y = 0,
		normal = {0.0, 0.0, -1.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {0.0, 1.0, 0.0},
		uv_x = 0,
		uv_y = 0,
		normal = {0.0, 0.0, -1.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {0.0, 0.0, 1.0},
		uv_x = 0,
		uv_y = 1,
		normal = {0.0, 0.0, 1.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {1.0, 0.0, 1.0},
		uv_x = 1,
		uv_y = 1,
		normal = {0.0, 0.0, 1.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {1.0, 1.0, 1.0},
		uv_x = 1,
		uv_y = 0,
		normal = {0.0, 0.0, 1.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {0.0, 1.0, 1.0},
		uv_x = 0,
		uv_y = 0,
		normal = {0.0, 0.0, 1.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {0.0, 0.0, 0.0},
		uv_x = 1,
		uv_y = 1,
		normal = {-1.0, 0.0, 0.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {0.0, 1.0, 0.0},
		uv_x = 1,
		uv_y = 0,
		normal = {-1.0, 0.0, 0.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {0.0, 1.0, 1.0},
		uv_x = 0,
		uv_y = 0,
		normal = {-1.0, 0.0, 0.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {0.0, 0.0, 1.0},
		uv_x = 0,
		uv_y = 1,
		normal = {-1.0, 0.0, 0.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {1.0, 0.0, 0.0},
		uv_x = 0,
		uv_y = 1,
		normal = {1.0, 0.0, 0.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {1.0, 1.0, 0.0},
		uv_x = 0,
		uv_y = 0,
		normal = {1.0, 0.0, 0.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {1.0, 1.0, 1.0},
		uv_x = 1,
		uv_y = 0,
		normal = {1.0, 0.0, 0.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {1.0, 0.0, 1.0},
		uv_x = 1,
		uv_y = 1,
		normal = {1.0, 0.0, 0.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {0.0, 0.0, 0.0},
		uv_x = 0,
		uv_y = 0,
		normal = {0.0, -1.0, 0.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {0.0, 0.0, 1.0},
		uv_x = 0,
		uv_y = 1,
		normal = {0.0, -1.0, 0.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {1.0, 0.0, 1.0},
		uv_x = 1,
		uv_y = 1,
		normal = {0.0, -1.0, 0.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {1.0, 0.0, 0.0},
		uv_x = 1,
		uv_y = 0,
		normal = {0.0, -1.0, 0.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {0.0, 1.0, 0.0},
		uv_x = 0,
		uv_y = 0,
		normal = {0.0, 1.0, 0.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {0.0, 1.0, 1.0},
		uv_x = 0,
		uv_y = 1,
		normal = {0.0, 1.0, 0.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {1.0, 1.0, 1.0},
		uv_x = 1,
		uv_y = 1,
		normal = {0.0, 1.0, 0.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
	{
		position = {1.0, 1.0, 0.0},
		uv_x = 1,
		uv_y = 0,
		normal = {0.0, 1.0, 0.0},
		color = {0.0, 0.0, 0.0, 1.0},
	},
}

baseIndices := [?]u32 {
	0,
	1,
	2,
	0,
	2,
	3, // 0,  1,  2,  0,  2,  3,
	2,
	1,
	0,
	3,
	2,
	0, // 6,  5,  4,  7,  6,  4,
	0,
	1,
	2,
	0,
	2,
	3, // 8,  9,  10, 8,  10, 11,
	2,
	1,
	0,
	3,
	2,
	0, // 14, 13, 12, 15, 14, 12,
	0,
	1,
	2,
	0,
	2,
	3, // 16, 17, 18, 16, 18, 19,
	2,
	1,
	0,
	3,
	2,
	0, // 22, 21, 20, 23, 22, 20,
}


BlockIdx :: distinct u32

BlockVtable :: struct {
	register_textures:
	#type proc "c" (block: ^Block, engine: ^VulkanEngine, atlas_builder: ^AtlasBuilder),
	register_model:   
	#type proc "c" (block: ^Block, engine: ^VulkanEngine, model_builder: ^ModelBuilder),
	populate_chunk:   
	#type proc "c" (
		block: ^Block,
		engine: ^VulkanEngine,
		chunk_builder: ^ChunkBuilder,
		chunk: ^Chunk,
		chunk_pos: [3]i32,
		in_chunk_position: [3]u32,
	),
	deinit:           
	#type proc "c" (block: ^Block, engine: ^VulkanEngine),
}

@(tag = "export")
Block :: struct {
	userdata:          rawptr,
	vtable:            BlockVtable,
	model_index_start: ModelIndex,
	model_name:        string,
}

Air :: Block {
	userdata = nil,
	vtable = BlockVtable {
		register_textures = proc "c" (
			block: ^Block,
			engine: ^VulkanEngine,
			atlas_builder: ^AtlasBuilder,
		) {},
		register_model = proc "c" (
			block: ^Block,
			engine: ^VulkanEngine,
			model_builder: ^ModelBuilder,
		) {},
		populate_chunk = proc "c" (
			block: ^Block,
			engine: ^VulkanEngine,
			chunk_builder: ^ChunkBuilder,
			chunk: ^Chunk,
			chunk_pos: [3]i32,
			in_chunk_position: [3]u32,
		) {},
		deinit = proc "c" (block: ^Block, engine: ^VulkanEngine) {},
	},
}

CubeData :: struct {
	name:    string,
	texture: CubeTexture,
}

CubeTexture :: struct {
	paths: [Face]string,
	size:  u32,
}

make_texture :: proc(
	top: string,
	bottom: string = "",
	positive_x: string = "",
	negative_x: string = "",
	positive_z: string = "",
	negative_z: string = "",
	size: u32 = 32,
) -> CubeTexture {
	bottom := bottom if bottom != "" else top
	positive_x := positive_x if positive_x != "" else top
	negative_x := negative_x if negative_x != "" else positive_x
	positive_z := positive_z if positive_z != "" else positive_x
	negative_z := negative_z if negative_z != "" else positive_z

	return {
		paths = {
			.PosY = top,
			.NegY = bottom,
			.PosX = positive_x,
			.NegX = negative_x,
			.PosZ = positive_z,
			.NegZ = negative_z,
		},
		size = size,
	}
}

register_cube :: proc(engine: ^VulkanEngine, name: string, texture: CubeTexture) {
	cube := create_cube(engine, name, texture)
	idx := len(engine.blocks)
	append(&engine.blocks, cube)
	engine.blocks_map[name] = cast(BlockIdx)idx
}

get_neighbor_pos :: proc "contextless" (chunk_pos: [3]u32, face: Face) -> [3]i64 {
	ipos := linalg.array_cast(chunk_pos, i64)
	switch face {
	case Face.NegZ:
		ipos.z -= 1
	case Face.PosZ:
		ipos.z += 1
	case Face.NegY:
		ipos.y -= 1
	case Face.PosY:
		ipos.y += 1
	case Face.NegX:
		ipos.x -= 1
	case Face.PosX:
		ipos.x += 1
	}

	return ipos
}

get_pos_in_neighbor_chunk :: proc "contextless" (
	chunk_pos: [3]u32,
	face: Face,
) -> (
	pos: [3]int,
	neighbor_chunk_offset: [3]i32 = {0, 0, 0},
	in_neighbor: bool,
) {
	ipos := get_neighbor_pos(chunk_pos, face)

	sizes := [3]i64{CHUNK_WIDTH, CHUNK_HEIGHT, CHUNK_WIDTH}

	for i in 0 ..< 3 {
		size := sizes[i]

		if ipos[i] < 0 {
			ipos[i] += size
			neighbor_chunk_offset[i] = -1
			in_neighbor = true
		} else if ipos[i] >= size {
			ipos[i] -= size
			neighbor_chunk_offset[i] = 1
			in_neighbor = true
		}
	}

	pos = linalg.array_cast(ipos, int)
	return
}

get_neigbor_pos_in_chunk :: proc "contextless" (
	chunk_pos: [3]u32,
	face: Face,
) -> (
	pos: [3]int = {},
	in_chunk: bool = true,
) {
	ipos := get_neighbor_pos(chunk_pos, face)

	#unroll for coord, i in ipos {
		if coord < 0 {
			in_chunk = false
			return
		}

		if i == 1 && coord >= CHUNK_HEIGHT {
			in_chunk = false
			return
		}

		if i != 1 && coord >= CHUNK_WIDTH {
			in_chunk = false
			return
		}
	}

	pos = linalg.array_cast(ipos, int)

	return
}

qualify_block_texture_path :: proc(path: string) -> string {
	base_block_path :: "assets/untrached/Faithful/assets/minecraft/textures/blocks"
	return fmt.aprintf("%s/%s", base_block_path, path)
}

create_cube :: proc(engine: ^VulkanEngine, name: string, texture: CubeTexture) -> Block {
	block: Block

	data := new(CubeData)
	data.texture = texture
	data.name = name

	block.userdata = data

	block.vtable.register_textures =
	proc "c" (block: ^Block, engine: ^VulkanEngine, atlas_builder: ^AtlasBuilder) {
		context = engine.ctx
		cube := cast(^CubeData)block.userdata

		for path in cube.texture.paths {
			already_exists := false
			full_path := qualify_block_texture_path(path)
			defer if already_exists {delete(full_path)}

			already_exists = atlas_builder_register_texture(
				atlas_builder,
				full_path,
				cube.texture.size,
			)

			log.infof("Registering block(%s) texture: %s", cube.name, full_path)
		}
	}

	block.vtable.register_model =
	proc "c" (block: ^Block, engine: ^VulkanEngine, model_builder: ^ModelBuilder) {
		context = engine.ctx

		cube_data := cast(^CubeData)block.userdata

		model: Model

		append(&model.vertices, ..modelVertices[:])

		y_offset := (1.0 / cast(f32)len(engine.texture_atlas.texture_map))
		for face, i in cube_data.texture.paths {
			full_path := qualify_block_texture_path(face)
			defer delete(full_path)
			texture_index := engine.texture_atlas.texture_map[full_path]

			for j in 0 ..< 4 {
				vertex := &model.vertices[cast(int)i * 4 + j]
				vertex.uv_x *= 1.0
				vertex.uv_y *= y_offset
				vertex.uv_y += y_offset * cast(f32)texture_index
			}
		}

		block.model_name = fmt.aprintf("cube/%s", cube_data.name)

		log.infof("Registering block: %s", block.model_name)

		model_builder_register_model(model_builder, block.model_name, model)
	}

	block.vtable.populate_chunk =
	proc "c" (
		block: ^Block,
		engine: ^VulkanEngine,
		chunk_builder: ^ChunkBuilder,
		chunk: ^Chunk,
		chunk_pos: [3]i32,
		in_chunk_position: [3]u32,
	) {
		context = engine.ctx

		vertices: [24]ChunkVertex //= make([dynamic]ChunkVertex, 0, len(baseChunkVertices))
		vertices_count := 0
		indices: [36]u32 // = make([dynamic]u32, 0, len(baseIndices))
		indices_count := 0
		max_index := cast(u32)len(chunk_builder.vertices)

		for face in 0 ..< 6 {
			neighbor_pos, in_chunk := get_neigbor_pos_in_chunk(in_chunk_position, cast(Face)face)
			if in_chunk {
				neigbor := chunk.blocks[chunk_calc_index(neighbor_pos)]
				if neigbor.block_id != 0 {
					continue
				}
			} else {
				pos_in_neighbor, neighbor_offset, in_neighbor := get_pos_in_neighbor_chunk(
					in_chunk_position,
					cast(Face)face,
				)
				if in_neighbor {
					neighbor_chunk_pos := chunk_pos + neighbor_offset
					neighbor_chunk, ok := &engine.chunks[neighbor_chunk_pos]
					if ok {
						neigbor := neighbor_chunk.blocks[chunk_calc_index(pos_in_neighbor)]
						if neigbor.block_id != 0 {
							continue
						}
					}
				}
			}

			base := face * 6
			for j in 0 ..< 6 {
				index := baseIndices[base + j] + cast(u32)vertices_count + max_index
				indices[indices_count] = index
				indices_count += 1
			}

			for j in 0 ..< 4 {
				vertex := make_chunk_vertex(
					in_chunk_position.x,
					in_chunk_position.y,
					in_chunk_position.z,
					block.model_index_start + baseChunkVertices[face * 4 + j].model_index,
				)

				vertices[vertices_count] = vertex
				vertices_count += 1
			}
		}

		chunk_builder_push_indices(chunk_builder, indices[:indices_count])
		chunk_builder_push_vertices(chunk_builder, vertices[:vertices_count])
	}

	block.vtable.deinit = proc "c" (block: ^Block, engine: ^VulkanEngine) {
		context = engine.ctx
		cube := cast(^CubeData)block.userdata
		free(cube)
		delete(block.model_name)
	}

	return block
}

@(private = "file")
@(export, link_name = "register_block")
register_block_c :: proc "c" (engine: ^VulkanEngine, name: cstring, block: Block) -> BlockIdx {
	context = engine.ctx

	name := string(name)
	return register_block(engine, name, block)
}

register_block :: proc(engine: ^VulkanEngine, name: string, block: Block) -> BlockIdx {
	rawIdx, err := append(&engine.blocks, block)
	if err != .None {
		return 0
	}

	idx := cast(BlockIdx)rawIdx

	engine.blocks_map[name] = idx

	return idx
}

ModelVertexBuilder :: struct {
	allocator: runtime.Allocator,
	vertices:  [dynamic]ModelVertex,
}

@(private = "file")
@(export, link_name = "model_vertex_builder_init")
model_vertex_builder_init_c :: proc "c" (engine: ^VulkanEngine, mvb: ^ModelVertexBuilder) {
	context = engine.ctx
	model_vertex_builder_init(engine, mvb)
}

model_vertex_builder_init :: proc(engine: ^VulkanEngine, mvb: ^ModelVertexBuilder) {
	mvb.allocator = context.allocator
	mvb.vertices = make([dynamic]ModelVertex)
}
