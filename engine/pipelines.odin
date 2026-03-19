package engine

import vk "vendor:vulkan"

PipelineBuilder :: struct {
	shaderStages:          [dynamic]vk.PipelineShaderStageCreateInfo,
	inputAssembly:         vk.PipelineInputAssemblyStateCreateInfo,
	rasterizer:            vk.PipelineRasterizationStateCreateInfo,
	colorBlendAttachment:  vk.PipelineColorBlendAttachmentState,
	multisampling:         vk.PipelineMultisampleStateCreateInfo,
	pipelineLayout:        vk.PipelineLayout,
	depthStencil:          vk.PipelineDepthStencilStateCreateInfo,
	renderInfo:            vk.PipelineRenderingCreateInfo,
	colorAttachmentformat: vk.Format,
}

pipeline_builder_clear :: proc(pb: ^PipelineBuilder) {
	pb.inputAssembly = vk.PipelineInputAssemblyStateCreateInfo {
		sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
	}

	pb.rasterizer = {
		sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
	}

	pb.colorBlendAttachment = {}

	pb.multisampling = {
		sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
	}

	pb.pipelineLayout = {}

	pb.depthStencil = {
		sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
	}

	pb.renderInfo = {
		sType = .PIPELINE_RENDERING_CREATE_INFO,
	}

	clear_dynamic_array(&pb.shaderStages)
}
