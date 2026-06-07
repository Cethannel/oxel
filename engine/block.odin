package engine

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:log"
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
}

CubeData :: struct {
	name:         string,
	path:         string,
	texture_size: u32,
}

register_cube :: proc(engine: ^VulkanEngine, name: string, texture: string, texture_size: u32) {
	cube := create_cube(engine, name, texture, texture_size)
	idx := len(engine.blocks)
	append(&engine.blocks, cube)
	engine.blocks_map[name] = cast(BlockIdx)idx
}

create_cube :: proc(
	engine: ^VulkanEngine,
	name: string,
	texture: string,
	texture_size: u32,
) -> Block {
	block: Block

	data := new(CubeData)
	data.path = texture
	data.name = name
	data.texture_size = texture_size

	block.userdata = data

	block.vtable.register_textures =
	proc "c" (block: ^Block, engine: ^VulkanEngine, atlas_builder: ^AtlasBuilder) {
		context = engine.ctx
		cube := cast(^CubeData)block.userdata

		log.infof("Registering block(%s) texture: %s", cube.name, cube.path)

		assert(
			atlas_builder_register_texture(atlas_builder, cube.name, cube.path, cube.texture_size),
			"Failed to register texture",
		)
	}

	block.vtable.register_model =
	proc "c" (block: ^Block, engine: ^VulkanEngine, model_builder: ^ModelBuilder) {
		context = engine.ctx

		cube_data := cast(^CubeData)block.userdata

		model: Model

		append(&model.vertices, ..modelVertices[:])

		i := engine.texture_atlas.texture_map[cube_data.name]

		for &vertex in model.vertices {
			y_offset := (1.0 / cast(f32)len(engine.texture_atlas.texture_map))
			vertex.uv_x *= 1.0
			vertex.uv_y *= y_offset
			vertex.uv_y += y_offset * cast(f32)i
		}

		name_buffer: [1024]u8

		name := fmt.aprintf("cube/%s", cube_data.name)

		log.infof("Registering block: %s", name)

		model_builder_register_model(model_builder, name, model)
	}

	block.vtable.populate_chunk =
	proc "c" (
		block: ^Block,
		engine: ^VulkanEngine,
		chunk_builder: ^ChunkBuilder,
		in_chunk_position: [3]u32,
	) {
		context = engine.ctx

		cube := cast(^CubeData)block.userdata

		indices := make([]u32, len(baseIndices))
		defer delete(indices)
		max_index := chunk_builder.start_index
		local_max := max_index
		for face in 0 ..< 6 {
			base := face * 6
			offset: u32 = cast(u32)face * 4
			for j in 0 ..< 6 {
				index := baseIndices[base + j] + offset + max_index
				indices[base + j] = index
				local_max = max(index, local_max)
			}
		}

		chunk_builder_push_indices(chunk_builder, indices[:])

		block := baseChunkVertices

		name_buffer: [1024]u8

		name := fmt.bprintf(name_buffer[:], "cube/%s", cube.name)

		for &vertex in block {
			vertex = make_chunk_vertex(
				in_chunk_position.x,
				in_chunk_position.y,
				in_chunk_position.z,
				engine.model_index_map[name] + vertex.model_index,
			)
		}
		chunk_builder_push_vertices(chunk_builder, block[:])
	}

	block.vtable.deinit = proc "c" (block: ^Block, engine: ^VulkanEngine) {
		context = engine.ctx
		cube := cast(^CubeData)block.userdata
		free(cube)
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
