package example_mod

import oxel "../engine"
import "core:fmt"
import "core:log"

@(export)
info_func :: proc(engine_info: oxel.EngineInfo) -> oxel.ModInfo {
	assert(engine_info.engine_version.minor > 0)

	fmt.printfln("Got engine: %v", engine_info)

	return {
		modded_version = oxel.make_version(0, 1, 0),
		mod_version = oxel.make_version(0, 1, 0),
		name = "oxel",
		init_func = init_func,
		deinit_func = deinit_func,
		register_blocks_func = register_blocks_func,
	}
}

@(export)
init_func :: proc(info: ^oxel.ModInfo, engine: ^oxel.VulkanEngine) {
	log.infof("Initialized mod: %s", info.name)
}

@(export)
deinit_func :: proc(info: ^oxel.ModInfo, engine: ^oxel.VulkanEngine) {
	log.infof("Deinitialized mod: %s", info.name)
}

@(export)
register_blocks_func :: proc(mod_info: ^oxel.ModInfo, engine: ^oxel.VulkanEngine) {
	oxel.register_cube(engine, mod_info.name, "stone", oxel.make_texture("stone.png"))
	oxel.register_cube(engine, mod_info.name, "dirt", oxel.make_texture("dirt.png"))
	oxel.register_cube(engine, mod_info.name, "planks_oak", oxel.make_texture("planks_oak.png"))
	oxel.register_cube(
		engine,
		mod_info.name,
		"log_oak",
		oxel.make_texture("log_oak_top.png", positive_x = "log_oak.png"),
	)
	oxel.register_cube(
		engine,
		mod_info.name,
		"grass_block",
		oxel.make_texture("grass_top.png", bottom = "dirt.png", positive_x = "grass_side.png"),
	)

	oxel.register_cube(engine, mod_info.name, "glass", oxel.make_texture("glass.png"), true)
}
