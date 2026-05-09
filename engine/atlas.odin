package engine

import "core:image"
import "core:log"
import "core:mem"
AtlasBuilder :: struct {
	textures: map[string]string,
}

atlas_builder_init :: proc(ab: ^AtlasBuilder, allocator := context.allocator) {
	ab.textures = make(map[string]string)
}

atlas_builder_register_texture :: proc(
	ab: ^AtlasBuilder,
	name: string,
	image_path: string,
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

	return true
}

atlas_builder_build :: proc(
	ab: ^AtlasBuilder,
	allocator := context.allocator,
) -> (
	data: []u8,
	ok: bool,
) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena, allocator, allocator)
	defer mem.dynamic_arena_free_all(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)
	texture_files := make([]image.Image, len(ab.textures))
	defer delete(texture_files)

	i := 0
	for k, v in ab.textures {
		defer i += 1

		img, err := image.load_from_file(v, {.alpha_add_if_missing})
		if err != nil {
			log.errorf("Failed to load image(%s): %e", v, err)
			return nil, false
		}
	}

	return nil, false
}
