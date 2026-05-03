package main

import "core:c"
import "core:fmt"
import "core:log"

import "engine"

main :: proc() {
	context.logger = log.create_console_logger()

	vulk := engine.init()
	defer engine.cleanup(&vulk)

	engine.run(&vulk)

	//stone := register_cube_full(&vulk, "stone", "textures/sone.png")
}
