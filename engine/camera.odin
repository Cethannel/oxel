package engine

import "core:math/linalg"
import "core:time"
import sdl2 "vendor:sdl2"

Camera :: struct {
	velocity: [3]f32,
	position: [3]f32,
	pitch:    f32,
	yaw:      f32,
}

camera_get_view_matrix :: proc(self: ^Camera) -> matrix[4, 4]f32 {
	camera_translation := linalg.matrix4_translate(self.position)
	camera_rotation := camera_get_rotation_matrix(self)
	return linalg.inverse(camera_translation * camera_rotation)
}

camera_get_rotation_matrix :: proc(self: ^Camera) -> matrix[4, 4]f32 {
	pitch_rotation := linalg.quaternion_angle_axis(self.pitch, [3]f32{1.0, 0.0, 0.0})
	yaw_rotation := linalg.quaternion_angle_axis(self.yaw, [3]f32{0.0, -1.0, 0.0})

	return(
		linalg.matrix4_from_quaternion(yaw_rotation) *
		linalg.matrix4_from_quaternion(pitch_rotation) \
	)
}

camera_process_sdl_event :: proc(self: ^Camera, event: ^sdl2.Event) {
	if (event.type == .KEYDOWN) {
		if (event.key.keysym.sym == .w) {self.velocity.z = -1}
		if (event.key.keysym.sym == .s) {self.velocity.z = 1}
		if (event.key.keysym.sym == .a) {self.velocity.x = -1}
		if (event.key.keysym.sym == .d) {self.velocity.x = 1}
		if (event.key.keysym.sym == .LSHIFT) {self.velocity.y = -1}
		if (event.key.keysym.sym == .SPACE) {self.velocity.y = 1}

		if (event.key.keysym.sym == .ESCAPE) {
			sdl2.SetRelativeMouseMode(!sdl2.GetRelativeMouseMode())
		}
	}

	if (event.type == .KEYUP) {
		if (event.key.keysym.sym == .w) {self.velocity.z = 0}
		if (event.key.keysym.sym == .s) {self.velocity.z = 0}
		if (event.key.keysym.sym == .a) {self.velocity.x = 0}
		if (event.key.keysym.sym == .d) {self.velocity.x = 0}
		if (event.key.keysym.sym == .LSHIFT) {self.velocity.y = 0}
		if (event.key.keysym.sym == .SPACE) {self.velocity.y = 0}
	}

	if (sdl2.GetRelativeMouseMode() && event.type == .MOUSEMOTION) {
		self.yaw += cast(f32)(event.motion.xrel) / 200.0
		self.pitch -= cast(f32)(event.motion.yrel) / 200.0
	}
}

camera_process_update :: proc(self: ^Camera, dt: time.Duration) {
	camera_rotation := camera_get_rotation_matrix(self)
	self.position +=
		(camera_rotation * vec3_to_vec4(self.velocity * cast(f32)time.duration_seconds(dt) * 5, 0.0)).xyz
}
