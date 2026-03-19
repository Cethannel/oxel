package engine

import vkb "../vkbootstrap/"
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
