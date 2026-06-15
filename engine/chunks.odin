package engine

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

chunk_mesh_gen :: proc(
	chunk_mesh: ^ChunkMesh,
	engine: ^VulkanEngine,
	chunk: ^Chunk,
	pos: [3]i32,
) -> vk.Result {
	chunk_builder: ChunkBuilder = {}
	chunk_builder_clear(&chunk_builder)
	defer chunk_builder_deinit(&chunk_builder)

	for block, idx in chunk.blocks {
		pos := linalg.array_cast(chunk_calc_pos(idx), u32)
		blk_data := &engine.blocks[block.block_id]
		blk_data.vtable.populate_chunk(blk_data, engine, &chunk_builder, pos)
	}

	chunk_mesh^ = chunk_builder_build(&chunk_builder, engine) or_return

	return .SUCCESS
}

chunk_mesh_render :: proc(engine: ^VulkanEngine, cmd: vk.CommandBuffer) {
	push_constants: GPUDrawPushConstants
	push_constants.worldMatrix = 1.

	fov := math.to_radians_f32(70.0)
	aspect := f32(engine.draw_extent.width) / f32(engine.draw_extent.height)
	near: f32 = 0.01

	projection := matrix4_perspective_reverse_z_infinite_f32(fov, aspect, near, true)

	view := linalg.matrix4_look_at_f32(
	engine.camera_pos, // eye
	{0, 0, 0}, // center (or a look target)
	{0, 1, 0}, // up
	)


	for pos, mesh in engine.chunk_meshes {
		model := linalg.matrix4_translate_f32(chunk_pos_to_world_pos(pos, f32))

		mvp := projection * view * model

		push_constants.worldMatrix = mvp
		push_constants.vertexBuffer = mesh.meshBuffers.vertexBufferAddress

		vk.CmdPushConstants(
			cmd,
			engine.meshPipelineLayout,
			{.VERTEX},
			0,
			size_of(GPUDrawPushConstants),
			&push_constants,
		)

		vk.CmdBindIndexBuffer(cmd, mesh.meshBuffers.indexBuffer.buffer, 0, .UINT32)

		vk.CmdDrawIndexed(
			cmd,
			mesh.size,
			1,
			0, // Offset
			0,
			0,
		)
	}
}

chunk_pos_to_world_pos_int_short :: proc(chunk_pos: [3]i32) -> [3]i32 {
	return chunk_pos_to_world_pos_int(chunk_pos, i32)
}

chunk_pos_to_world_pos_int :: proc(chunk_pos: [3]i32, $T: typeid) -> [3]T {
	world_int: [3]i32 = {
		chunk_pos.x * CHUNK_WIDTH,
		chunk_pos.y * CHUNK_HEIGHT,
		chunk_pos.y * CHUNK_WIDTH,
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
	for index in indices {
		self.start_index = max(self.start_index, index + 1)
	}

	append(&self.indices, ..indices)
}
