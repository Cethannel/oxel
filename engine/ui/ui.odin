package ui

import "core:fmt"
import "core:hash"

SizeKind :: enum {
	nil,
	Pixels,
	TextContent,
	PercentOfParentt,
	ChildrenSum,
}

Size :: struct {
	kind:       SizeKind,
	value:      f32,
	strictness: f32,
}

Rect :: struct {
	top_left:     [2]f32,
	bottom_right: [2]f32,
}

BoxIndex :: distinct u32

Axis2 :: enum {
	X,
	Y,
}

BoxFlags :: enum {
	Clickable,
	ViewScroll,
	DrawText,
	DrawBorder,
	DrawBackground,
	DrawDropShadow,
	Clip,
	HotAnimation,
	ActiveAnimation,
}

BoxFlagsSet :: bit_set[BoxFlags]

Key :: u64

Box :: struct {
	// :tree_links
	first:                      BoxIndex,
	last:                       BoxIndex,
	next:                       BoxIndex,
	prev:                       BoxIndex,
	parent:                     BoxIndex,

	// :hash_links
	hash_next:                  BoxIndex,
	hash_prev:                  BoxIndex,
	// key+generation info
	key:                        Key,
	last_frame_touched_index:   u64,

	// per-frame info provided by builders
	flags:                      BoxFlagsSet,
	string:                     string,
	semantic_size:              [Axis2]Size,

	// computed everey frame
	computed_relative_position: [Axis2]f32,
	computed_size:              [Axis2]f32,
	rect:                       Rect,

	// persistent data
	hot_t:                      f32,
	active_t:                   f32,
}

Comm :: struct {
	box:            BoxIndex,
	mouse:          [2]f32,
	drag_delta:     [2]f32,
	clicked:        bool,
	double_clicked: bool,
	right_clicked:  bool,
	pressed:        bool,
	released:       bool,
	dragging:       bool,
	hovering:       bool,
}

key_null :: proc() -> Key {
	return 0
}

key_from_string :: proc(str: string) -> Key {
	return key_from_bytes(transmute([]u8)str)
}

key_from_bytes :: proc(bytes: []u8) -> Key {
	return hash.crc64_iso_3306(bytes)
}

key_match :: proc(a: Key, b: Key) -> bool {
	return a == b
}

box_make :: proc(flags: BoxFlagsSet, str: string) -> BoxIndex {
	panic("unimplemented")
}

box_makef :: proc(flags: BoxFlagsSet, format: string, args: ..any) -> BoxIndex {
	str := fmt.aprintf(format, ..args)
	//defer delete(str)
	panic("unimplemented")
}

box_equip_display_string :: proc(box: BoxIndex, str: string) {}

box_equip_child_layout_axis :: proc(box: BoxIndex, axix: Axis2) {}

push_parent :: proc(box: BoxIndex) -> BoxIndex {
	panic("todo")
}

pop_parent :: proc() -> BoxIndex {
	panic("todo")
}

comm_from_box :: proc(box: BoxIndex) -> Comm {
	panic("todo")
}

button :: proc(str: string) -> Comm {
	box := box_make(
		{ 	// flags
			.Clickable,
			.DrawBorder,
			.DrawText,
			.DrawBackground,
			.HotAnimation,
			.ActiveAnimation,
		},
		str,
	)

	comm := comm_from_box(box)

	return comm
}
