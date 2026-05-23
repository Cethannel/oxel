package engine

import vkb "../vkbootstrap/"
import vma "../vma/"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:slice"
import vk "vendor:vulkan"

import "core:mem"

LoadShaderError :: union #shared_nil {
	os.Error,
	vkb.Error,
}

load_shader_module :: proc(
	filePath: string,
	device: vk.Device,
) -> (
	shader_module: vk.ShaderModule,
	err: LoadShaderError,
) {
	log.info("Loading shader: %s", filePath)

	file: os.Handle
	file, err = os.open(filePath)
	if err != nil {
		fmt.panicf("Failed to open shader: %s\n", filePath)
	}
	defer os.close(file)

	file_size := os.file_size(file) or_return

	buffer: [dynamic]u32
	defer delete(buffer)
	resize(&buffer, file_size / size_of(u32))

	os.seek(file, 0, 0) or_return

	os.read(file, mem.slice_to_bytes(buffer[:]))

	createInfo := vk.ShaderModuleCreateInfo {
		sType = .SHADER_MODULE_CREATE_INFO,
		pNext = nil,
	}

	createInfo.codeSize = len(buffer) * size_of(u32)
	createInfo.pCode = raw_data(buffer)

	shader_module = 0

	vkb.vk_check(vk.CreateShaderModule(device, &createInfo, nil, &shader_module)) or_return

	return shader_module, nil
}

pipeline_shader_stage_create_info :: proc(
	stage: vk.ShaderStageFlags,
	shaderModule: vk.ShaderModule,
	entry: cstring,
) -> vk.PipelineShaderStageCreateInfo {
	info: vk.PipelineShaderStageCreateInfo = {}
	info.sType = .PIPELINE_SHADER_STAGE_CREATE_INFO
	info.pNext = nil

	// shader stage
	info.stage = stage
	// module containing the code for this shader stage
	info.module = shaderModule
	// the entry point of the shader
	info.pName = entry
	return info
}

//< image_set
pipeline_layout_create_info :: proc() -> vk.PipelineLayoutCreateInfo {
	info: vk.PipelineLayoutCreateInfo = {}
	info.sType = .PIPELINE_LAYOUT_CREATE_INFO
	info.pNext = nil

	// empty defaults
	info.flags = {}
	info.setLayoutCount = 0
	info.pSetLayouts = nil
	info.pushConstantRangeCount = 0
	info.pPushConstantRanges = nil
	return info
}


matrix4_perspective_reverse_z_f32 :: proc "contextless" (
	fovy, aspect, near: f32,
	flip_y_axis := true,
) -> (
	m: linalg.Matrix4f32,
) #no_bounds_check {
	epsilon :: 0.00000095367431640625 // 2^-20 or about 10^-6
	fov_scale := 1 / math.tan(fovy * 0.5)

	m[0, 0] = fov_scale / aspect
	m[1, 1] = fov_scale

	// Set up reverse-Z configuration
	m[2, 2] = epsilon
	m[2, 3] = near * (1 - epsilon)
	m[3, 2] = -1

	// Handle Vulkan Y-flip if needed
	if flip_y_axis {
		m[1, 1] = -m[1, 1]
	}

	return
}
// Correct infinite-far reverse-Z perspective matrix for Vulkan
matrix4_perspective_reverse_z_infinite_f32 :: proc(
	fovy, aspect, near: f32,
	flip_y := true,
) -> linalg.Matrix4f32 {
	f := 1.0 / math.tan(fovy * 0.5)

	m: linalg.Matrix4f32 = linalg.MATRIX4F32_IDENTITY

	m[0, 0] = f / aspect // X scale
	m[1, 1] = f // Y scale (will be negated below if flip_y)

	// Reverse-Z + infinite far:
	m[2, 2] = 0.0
	m[2, 3] = near // important
	m[3, 2] = -1.0
	m[3, 3] = 0.0

	if flip_y {
		m[1, 1] = -m[1, 1] // Vulkan Y-down flip (this is the most common fix for stretching)
	}

	return m
}

assert_eq :: proc(left: $T, right: T) {
	if left != right {
		log.panicf("%v != %v", left, right)
	}
}

dupe :: proc(
	input: $T/[]$E,
	allocator := context.allocator,
) -> (
	res: T,
	err: mem.Allocator_Error,
) #optional_allocator_error {
	out := make(T, len(input)) or_return
	mem.copy(raw_data(out), raw_data(input), size_of(E) * len(input))
	return out, nil
}
