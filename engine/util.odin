package engine

import vkb "../vkbootstrap/"
import vma "../vma/"
import "core:fmt"
import "core:os"
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
