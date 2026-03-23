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

pipeline_builder_build :: proc(
	pb: ^PipelineBuilder,
	device: vk.Device,
) -> (
	pipeline: vk.Pipeline,
	err: vk.Result,
) {
	viewportState: vk.PipelineViewportStateCreateInfo = {}
	viewportState.sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO
	viewportState.pNext = nil

	viewportState.viewportCount = 1
	viewportState.scissorCount = 1

	colorBlending: vk.PipelineColorBlendStateCreateInfo = {}
	colorBlending.sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO

	colorBlending.logicOpEnable = false
	colorBlending.logicOp = .COPY
	colorBlending.attachmentCount = 1
	colorBlending.pAttachments = &pb.colorBlendAttachment

	vertexInputInfo: vk.PipelineVertexInputStateCreateInfo = {}
	vertexInputInfo.sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO

	pipelineInfo: vk.GraphicsPipelineCreateInfo = {}
	pipelineInfo.sType = .GRAPHICS_PIPELINE_CREATE_INFO
	pipelineInfo.pNext = &pb.renderInfo
	pipelineInfo.stageCount = cast(u32)len(pb.shaderStages)
	pipelineInfo.pStages = &pb.shaderStages[0]
	pipelineInfo.pVertexInputState = &vertexInputInfo
	pipelineInfo.pInputAssemblyState = &pb.inputAssembly
	pipelineInfo.pViewportState = &viewportState
	pipelineInfo.pRasterizationState = &pb.rasterizer
	pipelineInfo.pMultisampleState = &pb.multisampling
	pipelineInfo.pColorBlendState = &colorBlending
	pipelineInfo.pDepthStencilState = &pb.depthStencil
	pipelineInfo.layout = pb.pipelineLayout

	state := [?]vk.DynamicState{.VIEWPORT, .SCISSOR}

	dynamicInfo: vk.PipelineDynamicStateCreateInfo
	dynamicInfo.sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO
	dynamicInfo.dynamicStateCount = len(state)
	dynamicInfo.pDynamicStates = &state[0]

	pipelineInfo.pDynamicState = &dynamicInfo


	vk.CreateGraphicsPipelines(device, 0, 1, &pipelineInfo, nil, &pipeline) or_return

	return
}

pipeline_builder_set_shaders :: proc(
	pb: ^PipelineBuilder,
	vertexShader: vk.ShaderModule,
	fragmentShader: vk.ShaderModule,
) {
	clear(&pb.shaderStages)

	append(&pb.shaderStages, pipeline_shader_stage_create_info({.VERTEX}, vertexShader, "main"))

	append(
		&pb.shaderStages,
		pipeline_shader_stage_create_info({.FRAGMENT}, fragmentShader, "main"),
	)
}

pipeline_builder_set_topology :: proc(pb: ^PipelineBuilder, topology: vk.PrimitiveTopology) {
	pb.inputAssembly.topology = topology

	pb.inputAssembly.primitiveRestartEnable = false
}

pipeline_builder_set_polygon_mode :: proc(pb: ^PipelineBuilder, mode: vk.PolygonMode) {
	pb.rasterizer.polygonMode = mode
	pb.rasterizer.lineWidth = 1.0
}

pipeline_builder_set_cull_mode :: proc(
	pb: ^PipelineBuilder,
	cullMode: vk.CullModeFlags,
	frontFace: vk.FrontFace,
) {
	pb.rasterizer.cullMode = cullMode
	pb.rasterizer.frontFace = frontFace
}


pipeline_builder_set_multisampling_none :: proc(pb: ^PipelineBuilder) {
	pb.multisampling.sampleShadingEnable = false
	// multisampling defaulted to no multisampling (1 sample per pixel)
	pb.multisampling.rasterizationSamples = {._1}
	pb.multisampling.minSampleShading = 1.0
	pb.multisampling.pSampleMask = nil
	// no alpha to coverage either
	pb.multisampling.alphaToCoverageEnable = false
	pb.multisampling.alphaToOneEnable = false
}

pipeline_builder_disable_blending :: proc(pb: ^PipelineBuilder) {
	// default write mask
	pb.colorBlendAttachment.colorWriteMask = {.R, .G, .B, .A}
	// no blending
	pb.colorBlendAttachment.blendEnable = false
}

pipeline_builder_set_color_attachment_format :: proc(pb: ^PipelineBuilder, format: vk.Format) {
	pb.colorAttachmentformat = format
	pb.renderInfo.colorAttachmentCount = 1
	pb.renderInfo.pColorAttachmentFormats = &pb.colorAttachmentformat
}

pipeline_builder_set_depth_format :: proc(pb: ^PipelineBuilder, format: vk.Format) {
	pb.renderInfo.depthAttachmentFormat = format
}

pipeline_builder_disable_depthtest :: proc(pb: ^PipelineBuilder) {
	pb.depthStencil.depthTestEnable = false
	pb.depthStencil.depthWriteEnable = false
	pb.depthStencil.depthCompareOp = .NEVER
	pb.depthStencil.depthBoundsTestEnable = false
	pb.depthStencil.stencilTestEnable = false
	pb.depthStencil.front = {}
	pb.depthStencil.back = {}
	pb.depthStencil.minDepthBounds = 0.
	pb.depthStencil.maxDepthBounds = 1.
}

pipeline_builder_enable_depthtest :: proc(
	pb: ^PipelineBuilder,
	depthWriteEnable: b32,
	op: vk.CompareOp,
) {
	pb.depthStencil.depthTestEnable = true
	pb.depthStencil.depthWriteEnable = depthWriteEnable
	pb.depthStencil.depthCompareOp = op
	pb.depthStencil.depthBoundsTestEnable = false
	pb.depthStencil.stencilTestEnable = false
	pb.depthStencil.front = {}
	pb.depthStencil.back = {}
	pb.depthStencil.minDepthBounds = 0.
	pb.depthStencil.maxDepthBounds = 1.
}

pipeline_builder_enable_blending_additive :: proc(pb: ^PipelineBuilder) {
	pb.colorBlendAttachment.colorWriteMask = {.R, .G, .B, .A}
	pb.colorBlendAttachment.blendEnable = true
	pb.colorBlendAttachment.srcColorBlendFactor = .SRC_ALPHA
	pb.colorBlendAttachment.dstColorBlendFactor = .ONE
	pb.colorBlendAttachment.colorBlendOp = .ADD
	pb.colorBlendAttachment.srcAlphaBlendFactor = .ONE
	pb.colorBlendAttachment.dstAlphaBlendFactor = .ZERO
	pb.colorBlendAttachment.alphaBlendOp = .ADD
}

pipeline_builder_enable_blending_alphablend :: proc(pb: ^PipelineBuilder) {
	pb.colorBlendAttachment.colorWriteMask = {.R, .G, .B, .A}
	pb.colorBlendAttachment.blendEnable = true
	pb.colorBlendAttachment.srcColorBlendFactor = .SRC_ALPHA
	pb.colorBlendAttachment.dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA
	pb.colorBlendAttachment.colorBlendOp = .ADD
	pb.colorBlendAttachment.srcAlphaBlendFactor = .ONE
	pb.colorBlendAttachment.dstAlphaBlendFactor = .ZERO
	pb.colorBlendAttachment.alphaBlendOp = .ADD
}
