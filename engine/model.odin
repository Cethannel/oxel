package engine

ModelBuilder :: struct {
	models: map[string]Model,
}

model_builder_init :: proc(model_builder: ^ModelBuilder) {
	model_builder.models = make(map[string]Model)
}

model_builder_register_model :: proc(model_builder: ^ModelBuilder, name: string, model: Model) {
	model_builder.models[name] = model
}

model_builder_build :: proc(model_builder: ^ModelBuilder) -> [dynamic]ModelVertex {
	count: int = 0

	for _, model in model_builder.models {
		count += len(model.vertices)
	}

	vertices := make_dynamic_array_len_cap([dynamic]ModelVertex, 0, count)

	for name, model in model_builder.models {
		off: u32 = cast(u32)len(vertices)

		append(&vertices, ..model.vertices[:])

		delete(model.vertices)
	}

	delete(model_builder.models)

	return vertices
}

Model :: struct {
	vertices: [dynamic]ModelVertex,
}

ModelLookup :: struct {
	offsets: map[string]u32,
}
