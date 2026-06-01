package engine

import "core:image"
import "core:log"
import "core:math"
import "core:mem"

import vk "vendor:vulkan"

AtlasBuilder :: struct {
	textures:         map[string]string,
	max_texture_size: u32,
}

Atlas :: struct {
	texture_map:  map[string]u32,
	texture_size: u32,
	image:        AllocatedImage,
}

atlas_get_texture_offset :: proc(atlas: ^Atlas, texture_name: string) -> (offset: u32, ok: bool) {
	offset, ok = atlas.texture_map[texture_name]
	return
}

atlas_builder_init :: proc(ab: ^AtlasBuilder, allocator := context.allocator) {
	ab.textures = make(map[string]string)
}

atlas_builder_register_texture :: proc(
	ab: ^AtlasBuilder,
	name: string,
	image_path: string,
	size: u32,
) -> (
	ok: bool,
) {
	value, has := ab.textures[name]
	if has && value != image_path {
		log.errorf(
			"Reregistration of texture with different path\nPrevious: `%s`\nNew: `%s`",
			value,
			image_path,
		)
		return false
	}

	ab.textures[name] = image_path

	if size > ab.max_texture_size {
		ab.max_texture_size = size
	}

	return true
}

atlas_builder_build :: proc(
	ab: ^AtlasBuilder,
	engine: ^VulkanEngine,
	allocator := context.allocator,
) -> (
	atlas: Atlas,
	ok: bool = false,
) {
	context.allocator = allocator
	err: image.Error
	vk_err: vk.Result
	arena: mem.Dynamic_Arena

	texture_len := ab.max_texture_size * ab.max_texture_size

	data := make([]u32, texture_len * cast(u32)(len(ab.textures) + 1))
	defer delete(data, allocator = allocator)

	atlas.texture_map = make(map[string]u32, len(ab.textures))
	defer if err != nil || vk_err != .SUCCESS {delete(atlas.texture_map)}

	mem.dynamic_arena_init(&arena, allocator, allocator)
	defer mem.dynamic_arena_free_all(&arena)

	context.allocator = mem.dynamic_arena_allocator(&arena)

	CHECKER_DARK: u32 : 0xFF000000 // black
	CHECKER_LIGHT: u32 : 0xFFC71585 // medium violet red / pink

	half := ab.max_texture_size / 2
	for x in 0 ..< ab.max_texture_size {
		for y in 0 ..< ab.max_texture_size {
			color: u32 = CHECKER_DARK
			if (x < half && y < half) || (x >= half && y >= half) {
				color = CHECKER_LIGHT
			}
			data[x + y * ab.max_texture_size] = color
		}
	}

	atlas.texture_map["null"] = 0

	i: u32 = 1
	for k, v in ab.textures {
		defer i += 1

		img: ^image.Image
		img, err = image.load_from_file(v, {.alpha_add_if_missing})
		defer image.destroy(img)
		if err != nil {
			log.errorf("Failed to load image(%s): %e", v, err)
			return
		}
		if img.width != img.height {
			log.errorf("Missmatch in width and height for: %s", v)
			log.errorf("Width: %d\nHeight:%d", img.width, img.height)
			return
		}
		input := mem.slice_data_cast([]u32, img.pixels.buf[:])
		copy_square_image_scaled(
			input,
			cast(u32)img.width,
			data[i * texture_len:][:texture_len],
			ab.max_texture_size,
		)
		atlas.texture_map[k] = i
	}

	atlas.image, vk_err = create_image_with_data(
		engine,
		raw_data(data),
		vk.Extent3D{width = ab.max_texture_size, height = i * ab.max_texture_size, depth = 1},
		.R8G8B8A8_UNORM,
		{.SAMPLED},
	)

	delete(ab.textures)

	return atlas, true
}

copy_square_image_scaled :: proc(input: []u32, input_size: u32, output: []u32, output_size: u32) {
	assert_eq(cast(int)(input_size * input_size), len(input))
	assert_eq(cast(int)(output_size * output_size), len(output))
	assert(input_size <= output_size)

	scale_factor := output_size / input_size

	for in_x in 0 ..< input_size {
		for num_x in 0 ..< scale_factor {
			out_x := in_x * scale_factor + num_x
			for in_y in 0 ..< input_size {
				for num_y in 0 ..< scale_factor {
					out_y := in_y * scale_factor + num_x
					output[out_y * output_size + out_x] = input[in_y * input_size + in_x]
				}
			}
		}
	}
}

atlas_destroy :: proc(atlas: ^Atlas, engine: ^VulkanEngine) {
	delete(atlas.texture_map)
	destroy_image(engine, &atlas.image)
}
