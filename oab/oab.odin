package oab

import "core:c"
import "core:strings"
import sdl2 "vendor:sdl2"

import vk "vendor:vulkan"

import imgui_sdl2 "../vendor/gitlab.com/L-4/odin-imgui/imgui_impl_sdl2"

Window :: struct {
	sdl_window: ^sdl2.Window,
	name:       cstring,
}

init :: proc() -> (ok: bool) {
	return sdl2.Init({.VIDEO}) == 0
}

create_window :: proc(
	name: string,
	pos: [2]int,
	size: [2]u32,
) -> (
	window: Window,
	ok: bool = false,
) {
	window.name = strings.clone_to_cstring(name)
	defer if !ok {delete(window.name)}
	window.sdl_window = sdl2.CreateWindow(
		window.name,
		cast(c.int)pos.x,
		cast(c.int)pos.y,
		cast(c.int)size.x,
		cast(c.int)size.y,
		{.VULKAN, .RESIZABLE},
	)

	if window.sdl_window != nil {
		ok = true
	}

	return
}

destroy_window :: proc(window: ^Window) {
	sdl2.DestroyWindow(window.sdl_window)
	delete(window.name)
}

window_create_vulkan_surface :: proc(
	window: ^Window,
	vk_instance: vk.Instance,
) -> (
	surface: vk.SurfaceKHR,
	ok: bool,
) {
	ok = !!sdl2.Vulkan_CreateSurface(window.sdl_window, vk_instance, &surface)
	return
}

window_init_sdl2 :: proc(window: ^Window) -> bool {
	return imgui_sdl2.InitForVulkan(window.sdl_window)
}

window_get_size :: proc(#by_ptr window: Window) -> (width: u32, height: u32) {
	w, h: c.int
	sdl2.GetWindowSize(window.sdl_window, &w, &h)
	width = cast(u32)w
	height = cast(u32)h
	return
}

KeyEventType :: enum (u8) {
	Down,
	Up,
}

KeyboardEvent :: struct {
	type: KeyEventType,
}

Event :: union {}
