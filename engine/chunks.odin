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
					chunk.blocks[idx].block_id = engine.blocks_map["oxel:stone"]
				} else if world_pos.y == 128 {
					chunk.blocks[idx].block_id = engine.blocks_map["oxel:grass_block"]
				} else if world_pos.y == 129 && world_pos.x == 0 && world_pos.z == 0 {
					chunk.blocks[idx].block_id = engine.blocks_map["oxel:log_oak"]
				} else if world_pos.y == 129 && world_pos.x == 1 && world_pos.z == 0 {
					chunk.blocks[idx].block_id = engine.blocks_map["oxel:glass"]
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
	solid_mesh_buffers:       GPUMeshBuffers,
	solid_size:               u32,
	transparent_mesh_buffers: GPUMeshBuffers,
	transparent_size:         u32,
}

chunk_mesh_delete :: proc(engine: ^VulkanEngine, chunk_mesh: ^ChunkMesh) {
	destroy_buffer(engine, chunk_mesh.solid_mesh_buffers.indexBuffer)
	destroy_buffer(engine, chunk_mesh.solid_mesh_buffers.vertexBuffer)
	destroy_buffer(engine, chunk_mesh.transparent_mesh_buffers.indexBuffer)
	destroy_buffer(engine, chunk_mesh.transparent_mesh_buffers.vertexBuffer)
}

chunk_mesh_gen :: proc(engine: ^VulkanEngine, chunk: ^Chunk, pos: [3]i32) -> ChunkBuilder {
	chunk_builder: ChunkBuilder = {}
	chunk_builder_clear(&chunk_builder)
	reserve(&chunk_builder.solid_mesh.indices, CHUNK_WIDTH * CHUNK_WIDTH * CHUNK_HEIGHT * 32)
	reserve(&chunk_builder.solid_mesh.vertices, CHUNK_WIDTH * CHUNK_WIDTH * CHUNK_HEIGHT * 26)
	reserve(&chunk_builder.transparent_mesh.indices, CHUNK_WIDTH * CHUNK_WIDTH * CHUNK_HEIGHT * 32)
	reserve(
		&chunk_builder.transparent_mesh.vertices,
		CHUNK_WIDTH * CHUNK_WIDTH * CHUNK_HEIGHT * 26,
	)

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

MeshBuilder :: struct {
	vertices:    [dynamic]ChunkVertex,
	indices:     [dynamic]u32,
	start_index: u32,
}

mesh_builder_clear :: proc(mesh_builder: ^MeshBuilder) {
	clear(&mesh_builder.vertices)
	clear(&mesh_builder.indices)
	mesh_builder.start_index = 0
}

mesh_builder_deinit :: proc(mesh_builder: ^MeshBuilder) {
	delete(mesh_builder.vertices)
	delete(mesh_builder.indices)
}

ChunkBuilder :: struct {
	solid_mesh:       MeshBuilder,
	transparent_mesh: MeshBuilder,
}

chunk_builder_clear :: proc(chunk_builder: ^ChunkBuilder) {
	mesh_builder_clear(&chunk_builder.solid_mesh)
	mesh_builder_clear(&chunk_builder.transparent_mesh)
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

		//if len(chunk_builder.vertices) == 0 || len(chunk_builder.indices) == 0 {
		//	continue
		//}

		if len(chunk_builder.solid_mesh.vertices) != 0 &&
		   len(chunk_builder.solid_mesh.indices) != 0 {
			append(
				&create_upload_infos,
				buffer_create_upload_info(
					&mesh.solid_mesh_buffers.vertexBuffer,
					&mesh.solid_mesh_buffers.vertexBufferAddress,
					chunk_builder.solid_mesh.vertices[:],
					.SSBO,
				),
				buffer_create_upload_info(
					&mesh.solid_mesh_buffers.indexBuffer,
					nil,
					chunk_builder.solid_mesh.indices[:],
					.Index,
				),
			)
		}

		if len(chunk_builder.transparent_mesh.vertices) != 0 &&
		   len(chunk_builder.transparent_mesh.indices) != 0 {
			append(
				&create_upload_infos,
				buffer_create_upload_info(
					&mesh.transparent_mesh_buffers.vertexBuffer,
					&mesh.transparent_mesh_buffers.vertexBufferAddress,
					chunk_builder.transparent_mesh.vertices[:],
					.SSBO,
				),
				buffer_create_upload_info(
					&mesh.transparent_mesh_buffers.indexBuffer,
					nil,
					chunk_builder.transparent_mesh.indices[:],
					.Index,
				),
			)
		}

		mesh.solid_size = cast(u32)len(chunk_builder.solid_mesh.indices)
		mesh.transparent_size = cast(u32)len(chunk_builder.transparent_mesh.indices)
	}

	create_and_upload_ssbo(engine, create_upload_infos[:]) or_return

	return
}

chunk_builder_deinit :: proc(chunk_builder: ^ChunkBuilder) {
	mesh_builder_deinit(&chunk_builder.solid_mesh)
	mesh_builder_deinit(&chunk_builder.transparent_mesh)
}

chunk_builder_push_solid_vertex :: proc(chunk_builder: ^ChunkBuilder, vertex: ChunkVertex) {
	append(&chunk_builder.solid_mesh.vertices, vertex)
}

chunk_builder_push_transparent_vertex :: proc(chunk_builder: ^ChunkBuilder, vertex: ChunkVertex) {
	append(&chunk_builder.transparent_mesh.vertices, vertex)
}

chunk_builder_push_solid_vertices :: proc(chunk_builder: ^ChunkBuilder, vertices: []ChunkVertex) {
	append(&chunk_builder.solid_mesh.vertices, ..vertices)
}

chunk_builder_push_transparent_vertices :: proc(
	chunk_builder: ^ChunkBuilder,
	vertices: []ChunkVertex,
) {
	append(&chunk_builder.transparent_mesh.vertices, ..vertices)
}

chunk_builder_push_solid_index :: proc(self: ^ChunkBuilder, index: u32) {
	self.solid_mesh.start_index = max(self.solid_mesh.start_index, index + 1)
	append(&self.solid_mesh.indices, index)
}

chunk_builder_push_transparent_index :: proc(self: ^ChunkBuilder, index: u32) {
	self.transparent_mesh.start_index = max(self.transparent_mesh.start_index, index + 1)
	append(&self.transparent_mesh.indices, index)
}

chunk_builder_push_solid_indices :: proc(self: ^ChunkBuilder, indices: []u32) {
	self.solid_mesh.start_index = cast(u32)len(self.solid_mesh.vertices)

	append(&self.solid_mesh.indices, ..indices)
}

chunk_builder_push_transparent_indices :: proc(self: ^ChunkBuilder, indices: []u32) {
	self.transparent_mesh.start_index = cast(u32)len(self.transparent_mesh.vertices)

	append(&self.transparent_mesh.indices, ..indices)
}

world_to_chunk_pos :: proc(world_pos: [3]i32) -> (chunk_pos: [3]i32, in_chunk_pos: [3]i32) {
	chunk_pos.xz = world_pos.xz / CHUNK_WIDTH
	chunk_pos.y = world_pos.y / CHUNK_HEIGHT
	chunk_pos.xz = world_pos.xz % CHUNK_WIDTH
	chunk_pos.y = world_pos.y % CHUNK_HEIGHT
	return
}
