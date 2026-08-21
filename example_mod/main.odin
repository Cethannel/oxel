package example_mod

import "../modding"
import "core:fmt"

@(export)
info_func :: proc(engine_info: modding.EngineInfo) -> modding.ModInfo {
	assert(engine_info.engine_version.minor > 0)

	fmt.printfln("Got engine: %v", engine_info)

	return {
		modded_version = modding.make_version(0, 1, 0),
		mod_version = modding.make_version(0, 1, 0),
		name = "example_mod",
	}
}
