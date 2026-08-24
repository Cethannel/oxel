package engine

import "core:dynlib"
import "core:fmt"

Version :: struct #packed {
	major: u8,
	minor: u8,
	patch: u8,
}

make_version :: proc(major: u8, minor: u8, patch: u8) -> Version {
	return Version{major, minor, patch}
}

version_string :: proc(version: Version) -> string {
	return fmt.aprintf("%d.%d.%d", version.major, version.minor, version.patch)
}

EngineInfo :: struct {
	engine_version: Version,
}

ModInfo :: struct {
	modded_version:       Version,
	mod_version:          Version,
	name:                 string,
	user_data:            ^rawptr,
	init_func:            ModInitFunc,
	deinit_func:          ModDeinitFunc,
	register_blocks_func: ModRegisterBlocksFunc,
}

Mod :: struct {
	info: ModInfo,
	lib:  dynlib.Library,
}

ModInfoFunc :: #type proc(engine_info: EngineInfo) -> ModInfo

ModInitFunc :: #type proc(info: ^ModInfo, engine: ^VulkanEngine)

ModDeinitFunc :: #type proc(info: ^ModInfo, engine: ^VulkanEngine)

ModRegisterBlocksFunc :: #type proc(info: ^ModInfo, engine: ^VulkanEngine)

load_mod :: proc(engine: ^VulkanEngine, path: string) -> (mod: Mod, ok: bool) {
	lib: dynlib.Library
	lib, ok = dynlib.load_library(path)
	if !ok {
		fmt.eprintln("Failed to load library:", dynlib.last_error())
		return
	}
	defer if !ok {dynlib.unload_library(lib)}

	// Get a symbol (procedure or variable)
	addr: rawptr
	addr, ok = dynlib.symbol_address(lib, "info_func")
	if !ok {
		fmt.eprintln("Symbol not found:", dynlib.last_error())
		return
	}

	my_func := cast(ModInfoFunc)addr
	result := my_func(EngineInfo{engine_version = make_version(0, 1, 0)})
	mod = Mod {
		info = result,
		lib  = lib,
	}
	return
}
