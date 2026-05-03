package engine

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

baseVertices := [?]Vertex {
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

Block :: struct {}

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
