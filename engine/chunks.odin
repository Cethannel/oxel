package engine

import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"
import vk "vendor:vulkan"

CHUNK_WIDTH :: 16
CHUNK_HEIGHT :: 256

CHUNK_SIZE :: CHUNK_WIDTH * CHUNK_HEIGHT * CHUNK_WIDTH

Chunk :: struct {
	blocks: #soa[CHUNK_SIZE]ChunkBlock,
}

chunk_calc_index :: proc "contextless" (pos: [3]int) -> int {
	return pos.x + pos.y * CHUNK_WIDTH + pos.z * (CHUNK_WIDTH * CHUNK_HEIGHT)
}

chunk_calc_pos :: proc "contextless" (index: int) -> [3]int {
	x := index % CHUNK_WIDTH
	y := (index / CHUNK_WIDTH) % CHUNK_HEIGHT
	z := index / (CHUNK_WIDTH * CHUNK_HEIGHT)
	return [3]int{x, y, z}
}

chunk_gen :: proc(engine: ^VulkanEngine, chunk: ^Chunk, chunk_pos: [3]i32) {
	world_pos := chunk_pos_to_world_pos(chunk_pos, int)

	for y in 0 ..< CHUNK_HEIGHT {
		for x in 0 ..< CHUNK_WIDTH {
			for z in 0 ..< CHUNK_WIDTH {
				in_chunk_pos: [3]int = {x, y, z}
				world_pos := in_chunk_pos + world_pos
				idx := chunk_calc_index(in_chunk_pos)
				chunk.blocks[idx] = {}
				if world_pos.y < 128 {
					chunk.blocks[idx].block_id = engine.blocks_map["stone"]
				} else if world_pos.y == 129 && world_pos.x == 0 && world_pos.z == 0 {
					chunk.blocks[idx].block_id = engine.blocks_map["log_oak"]
				}
			}
		}
	}
}

chunk_gen_blocks :: proc(engine: ^VulkanEngine, chunk: ^Chunk) {
	mem.zero_item(chunk)

	for _, i in engine.blocks {
		idx := chunk_calc_index({0, i, 0})
		chunk.blocks[idx].block_id = cast(BlockIdx)i
	}
}

ChunkBlock :: struct {
	block_id:            BlockIdx,
	block_chunk_data_id: u16,
}

ChunkMesh :: struct {
	meshBuffers: GPUMeshBuffers,
	size:        u32,
}

chunk_mesh_delete :: proc(engine: ^VulkanEngine, chunk_mesh: ^ChunkMesh) {
	destroy_buffer(engine, chunk_mesh.meshBuffers.indexBuffer)
	destroy_buffer(engine, chunk_mesh.meshBuffers.vertexBuffer)
}

chunk_mesh_gen :: proc(engine: ^VulkanEngine, chunk: ^Chunk, pos: [3]i32) -> ChunkBuilder {
	chunk_builder: ChunkBuilder = {}
	chunk_builder_clear(&chunk_builder)
	reserve(&chunk_builder.indices, CHUNK_WIDTH * CHUNK_WIDTH * CHUNK_HEIGHT * 32)
	reserve(&chunk_builder.vertices, CHUNK_WIDTH * CHUNK_WIDTH * CHUNK_HEIGHT * 26)

	for z in u32(0) ..< CHUNK_WIDTH {
		for y in u32(0) ..< CHUNK_HEIGHT {
			for x in u32(0) ..< CHUNK_WIDTH {
				idx := chunk_calc_index({int(x), int(y), int(z)})
				block := chunk.blocks[idx]
				if block.block_id == 0 {continue}
				blk_data := &engine.blocks[block.block_id]
				blk_data.vtable.populate_chunk(
					blk_data,
					engine,
					&chunk_builder,
					chunk,
					pos,
					{x, y, z},
				)
			}
		}
	}


	return chunk_builder
}

chunk_pos_to_world_pos_int_short :: proc(chunk_pos: [3]i32) -> [3]i32 {
	return chunk_pos_to_world_pos_int(chunk_pos, i32)
}

chunk_pos_to_world_pos_int :: proc(chunk_pos: [3]i32, $T: typeid) -> [3]T {
	world_int: [3]i32 = {
		chunk_pos.x * CHUNK_WIDTH,
		chunk_pos.y * CHUNK_HEIGHT,
		chunk_pos.z * CHUNK_WIDTH,
	}
	return linalg.array_cast(world_int, T)
}

chunk_pos_to_world_pos :: proc {
	chunk_pos_to_world_pos_int_short,
	chunk_pos_to_world_pos_int,
}

ChunkBuilder :: struct {
	vertices:    [dynamic]ChunkVertex,
	indices:     [dynamic]u32,
	start_index: u32,
}

chunk_builder_clear :: proc(chunk_builder: ^ChunkBuilder) {
	clear(&chunk_builder.vertices)
	clear(&chunk_builder.indices)
	chunk_builder.start_index = 0
}

chunk_builder_build_batch :: proc(
	chunk_builders: []ChunkBuilder,
	engine: ^VulkanEngine,
) -> (
	meshes: []ChunkMesh,
	err: vk.Result,
) {
	meshes = make([]ChunkMesh, len(chunk_builders))

	create_upload_infos: [dynamic]BufferCreateUploadInfo
	reserve(&create_upload_infos, len(chunk_builders) * 2)
	defer delete(create_upload_infos)

	for i in 0 ..< len(chunk_builders) {
		mesh := &meshes[i]
		chunk_builder := chunk_builders[i]

		if len(chunk_builder.vertices) == 0 || len(chunk_builder.indices) == 0 {
			continue
		}

		append(
			&create_upload_infos,
			buffer_create_upload_info(
				&mesh.meshBuffers.vertexBuffer,
				&mesh.meshBuffers.vertexBufferAddress,
				chunk_builder.vertices[:],
				.SSBO,
			),
			buffer_create_upload_info(
				&mesh.meshBuffers.indexBuffer,
				nil,
				chunk_builder.indices[:],
				.Index,
			),
		)

		mesh.size = cast(u32)len(chunk_builder.indices)
	}

	create_and_upload_ssbo(engine, create_upload_infos[:]) or_return

	return
}

chunk_builder_build :: proc(
	chunk_builder: ^ChunkBuilder,
	engine: ^VulkanEngine,
) -> (
	mesh: ChunkMesh,
	err: vk.Result,
) {
	create_upload_infos := [?]BufferCreateUploadInfo {
		buffer_create_upload_info(
			&mesh.meshBuffers.vertexBuffer,
			&mesh.meshBuffers.vertexBufferAddress,
			chunk_builder.vertices[:],
			.SSBO,
		),
		buffer_create_upload_info(
			&mesh.meshBuffers.indexBuffer,
			nil,
			chunk_builder.indices[:],
			.Index,
		),
	}
	create_and_upload_ssbo(engine, create_upload_infos[:]) or_return

	mesh.size = cast(u32)len(chunk_builder.indices)

	return
}

chunk_builder_deinit :: proc(chunk_builder: ^ChunkBuilder) {
	delete(chunk_builder.vertices)
	delete(chunk_builder.indices)
}

chunk_builder_push_vertex :: proc(chunk_builder: ^ChunkBuilder, vertex: ChunkVertex) {
	append(&chunk_builder.vertices, vertex)
}

chunk_builder_push_vertices :: proc(chunk_builder: ^ChunkBuilder, vertices: []ChunkVertex) {
	append(&chunk_builder.vertices, ..vertices)
}

chunk_builder_push_index :: proc(self: ^ChunkBuilder, index: u32) {
	self.start_index = max(self.start_index, index + 1)
	append(&self.indices, index)
}

chunk_builder_push_indices :: proc(self: ^ChunkBuilder, indices: []u32) {
	self.start_index = cast(u32)len(self.vertices)

	append(&self.indices, ..indices)
}
