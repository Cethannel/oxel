package engine

import "core:log"
import "core:math/linalg"
import "core:sync"
import "core:sync/chan"
import "core:thread"

WorkerThreadArgs :: struct {
	engine:         ^VulkanEngine,
	should_run:     bool,
	mesh_send_chan: chan.Chan(MeshMessage, .Send),
}

MeshMessage :: struct {
	mesh: ChunkMesh,
	pos:  [3]i32,
}

worker_thread_proc :: proc(args: ^WorkerThreadArgs) {
	log.infof("Stated worker")

	chunks: map[[3]i32]Chunk = make(map[[3]i32]Chunk)

	chunks_to_gen, err := chan.create_buffered(chan.Chan([3]i32), 1024, context.allocator)
	if err != nil {
		panic("Failed to create channel")
	}
	defer chan.destroy(chunks_to_gen)

	meshes_to_gen: chan.Chan([3]i32)
	meshes_to_gen, err = chan.create_buffered(chan.Chan([3]i32), 1024, context.allocator)
	if err != nil {
		panic("Failed to create channel")
	}
	defer chan.destroy(meshes_to_gen)

	BATCH_SIZE :: 32
	coords: [BATCH_SIZE][3]i32
	chunk_builders: [BATCH_SIZE]ChunkBuilder
	chunk_meshes: [BATCH_SIZE]ChunkMesh

	for sync.atomic_load(&args.should_run) {
		pos, ok := chan.try_recv(chunks_to_gen)
		for ok {
			defer {
				pos, ok = chan.try_recv(chunks_to_gen)
			}

			chunks[pos] = Chunk{}
			chunk_gen(args.engine, &chunks[pos], pos)

			_ = chan.try_send(meshes_to_gen, pos)
		}

		mesh: {
			mesh_count := 0
			mesh_pos, mesh_ok := chan.try_recv(meshes_to_gen)
			for mesh_ok {
				defer {
					if mesh_count < BATCH_SIZE {
						mesh_pos, mesh_ok = chan.try_recv(meshes_to_gen)
					}
				}

				chunk_builders[mesh_count] = chunk_mesh_gen(
					args.engine,
					&chunks[mesh_pos],
					mesh_pos,
				)
				coords[mesh_count] = mesh_pos
				shrink_dynamic_array(&chunk_builders[mesh_count].indices)
				shrink_dynamic_array(&chunk_builders[mesh_count].vertices)
				mesh_count += 1

				if mesh_count >= BATCH_SIZE {
					break
				}
			}

			meshes, err := chunk_builder_build_batch(chunk_builders[:mesh_count], args.engine)
			if err != nil {
				log.errorf("Failed to build batch: %v", err)
				for pos in coords[:mesh_count] {
					_ = chan.try_send(meshes_to_gen, pos)
				}
				break mesh
			}
			defer delete(meshes)

			// :send_mesh
			for pos, idx in coords[:mesh_count] {
				defer chunk_builder_deinit(&chunk_builders[idx])
				ok := chan.try_send(
					args.mesh_send_chan,
					MeshMessage{mesh = meshes[idx], pos = pos},
				)
				if !ok {
					log.errorf("Failed to send mesh: %v", pos)
					chunk_mesh_delete(args.engine, &meshes[idx])
				}
			}
		}

		gen_in_render_distance(args.engine, &chunks, chan.as_send(chunks_to_gen))

		thread.yield()
	}
}

gen_in_render_distance :: proc(
	engine: ^VulkanEngine,
	chunks: ^map[[3]i32]Chunk,
	chunks_to_gen: chan.Chan([3]i32, .Send),
) {
	player_chunk_pos, _ := world_to_chunk_pos(linalg.array_cast(engine.main_camera.position, i32))

	for x in 0 ..< engine.render_distance {
		for z in 0 ..< engine.render_distance {
			offset := [3]i32{x, 0, z}
			chunk_pos := player_chunk_pos + offset
			chunk_pos.y = 0

			_, ok := chunks[chunk_pos]
			if !ok {
				_ = chan.try_send(chunks_to_gen, chunk_pos)
			}
		}
	}
}
