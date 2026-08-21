package modding

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
	modded_version: Version,
	mod_version:    Version,
	name:           string,
}

ModInfoFunc :: #type proc(engine_info: EngineInfo) -> ModInfo
