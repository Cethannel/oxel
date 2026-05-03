package engine

import "core:math"
import "core:math/linalg"
import vk "vendor:vulkan"

CHUNK_WIDTH :: 16
CHUNK_HEIGHT :: 256


Chunk :: struct {
	blocks: [CHUNK_WIDTH][CHUNK_HEIGHT]#soa[CHUNK_WIDTH]ChunkBlock,
}

ChunkBlock :: struct {
	block_id:            BlockIdx,
	block_chunk_data_id: u16,
}

ChunkMesh :: struct {
	pos:         [2]i32,
	meshBuffers: GPUMeshBuffers,
	size:        u32,
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


	for mesh, i in engine.chunk_meshes {
		model := linalg.matrix4_translate_f32(chunk_pos_to_world_pos(mesh.pos))

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

gen_chunk :: proc(engine: ^VulkanEngine, pos: [2]i32) {
}

chunk_pos_to_world_pos :: proc(chunk_pos: [2]i32) -> [3]f32 {
	world_int: [3]i32 = {chunk_pos.x * 16, 0, chunk_pos.y * 16}
	return linalg.array_cast(world_int, f32)
}
