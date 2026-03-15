package main

import "core:fmt"

import "engine"

main :: proc() {
	vulk := engine.init()
	defer engine.cleanup(&vulk)

	engine.run(&vulk)
}
