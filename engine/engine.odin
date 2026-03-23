package engine

import "core:c"
import "core:flags"
import "core:log"
import "core:math/linalg"
import "core:mem"
import sdl2 "vendor:sdl2"
import vk "vendor:vulkan"

import "core:fmt"

import "core:math"
import "core:time"

import vkb "../vkbootstrap/"

import vma "../vma/"

import imgui "../vendor/gitlab.com/L-4/odin-imgui"
import imgui_sdl2 "../vendor/gitlab.com/L-4/odin-imgui/imgui_impl_sdl2"
import imgui_vulkan "../vendor/gitlab.com/L-4/odin-imgui/imgui_impl_vulkan"

DeinitFunc :: proc(engine: ^VulkanEngine)

FrameData :: struct {
	command_pool:        vk.CommandPool,
	main_command_buffer: vk.CommandBuffer,
	swapchain_semaphore: vk.Semaphore,
	render_fence:        vk.Fence,
}

AllocateImage :: struct {
	image:        vk.Image,
	image_view:   vk.ImageView,
	allocation:   vma.Allocation,
	image_extent: vk.Extent3D,
	image_format: vk.Format,
}

ComputeEffect :: struct {
	name:     string,
	pipeline: vk.Pipeline,
	layout:   vk.PipelineLayout,
	data:     ComputePushConstants,
}

AllocatedBuffer :: struct {
	buffer:     vk.Buffer,
	allocation: vma.Allocation,
	info:       vma.Allocation_Info,
}

Vertex :: struct {
	position: [3]f32,
	uv_x:     f32,
	normal:   [3]f32,
	uv_y:     f32,
	color:    [4]f32,
}

// holds the resources needed for a mesh
GPUMeshBuffers :: struct {
	indexBuffer:         AllocatedBuffer,
	vertexBuffer:        AllocatedBuffer,
	vertexBufferAddress: vk.DeviceAddress,
}

// push constants for our mesh object draws
GPUDrawPushConstants :: struct {
	worldMatrix:  matrix[4, 4]f32,
	vertexBuffer: vk.DeviceAddress,
}

FRAME_OVERLAP :: 2

VulkanEngine :: struct {
	deinitFuncs:                  [dynamic]DeinitFunc,
	frame_number:                 int,
	stop_rendering:               bool,
	window_extent:                vk.Extent2D,
	window:                       ^sdl2.Window,
	instance:                     ^vkb.Instance,
	device:                       ^vkb.Device,
	surface:                      vk.SurfaceKHR,
	is_initialized:               bool,
	swapchain:                    ^vkb.Swapchain,
	swapchain_images:             []vk.Image,
	render_semaphores:            []vk.Semaphore,
	swapchain_image_views:        []vk.ImageView,
	swapchain_extent:             vk.Extent2D,
	frames:                       [FRAME_OVERLAP]FrameData,
	graphics_queue:               vk.Queue,
	graphics_queue_family:        u32,
	allocator:                    vma.Allocator,
	draw_image:                   AllocateImage,
	depth_image:                  AllocateImage,
	draw_extent:                  vk.Extent2D,
	render_scale:                 f32,
	resize_requested:             bool,
	//
	global_descriptor_allocator:  DescriptorAllocator,
	draw_image_descriptors:       vk.DescriptorSet,
	draw_image_descriptor_layout: vk.DescriptorSetLayout,
	//
	gradient_pipeline_layout:     vk.PipelineLayout,
	// Imgui
	imm_fence:                    vk.Fence,
	imm_command_buffer:           vk.CommandBuffer,
	imm_command_pool:             vk.CommandPool,
	imgui_pool:                   vk.DescriptorPool,

	//
	backgroundEffects:            [dynamic]ComputeEffect,
	currentBackgroundEffect:      int,

	//
	meshPipelineLayout:           vk.PipelineLayout,
	meshPipeline:                 vk.Pipeline,

	// :gltf test
	testMeshes:                   [dynamic]MeshAsset,
}

ComputePushConstants :: struct {
	data1: [4]f32,
	data2: [4]f32,
	data3: [4]f32,
	data4: [4]f32,
}

@(private)
bEnableValidationLayers := true

init :: proc() -> VulkanEngine {
	engine := VulkanEngine {
		frame_number   = 0,
		window_extent  = {1700, 900},
		stop_rendering = false,
		window         = nil,
		is_initialized = false,
	}

	assert(sdl2.Init(sdl2.InitFlags{.VIDEO}) == 0, "Failed to initalize SDL")

	engine.window = sdl2.CreateWindow(
		"VulkanEngine",
		0,
		0,
		cast(c.int)engine.window_extent.width,
		cast(c.int)engine.window_extent.height,
		sdl2.WindowFlags{.VULKAN, .RESIZABLE},
	)
	append(&engine.deinitFuncs, proc(engine: ^VulkanEngine) {sdl2.DestroyWindow(engine.window)})

	err := init_vulkan(&engine)
	if err != nil {
		fmt.panicf("Failed to initalize vulkan: %s", err)
	}

	assert(init_swapchain(&engine) == nil, "Failed to initalize swapchain")

	assert(init_commands(&engine) == .SUCCESS, "Failed to initalize commands")

	assert(init_sync_structures(&engine) == .SUCCESS, "Failed to initalize sync features")

	init_descriptors(&engine)

	init_pipelines(&engine)

	assert(init_imgui(&engine) == .SUCCESS, "Failed to initialize imgui")

	assert(init_default_data(&engine) == .SUCCESS, "Failed to init default data")

	engine.render_scale = 1.0
	engine.is_initialized = true

	return engine
}

run :: proc(engine: ^VulkanEngine) {
	assert(engine.is_initialized, "Engine is not initalized")

	e: sdl2.Event

	quit := false

	for (!quit) {
		for (sdl2.PollEvent(&e)) {
			if imgui_sdl2.ProcessEvent(&e) {
				continue
			}

			if e.type == .QUIT {
				quit = true
			}

			if e.type == .WINDOWEVENT {
				#partial switch e.window.event {
				case .MINIMIZED:
					engine.stop_rendering = true
				case .RESTORED:
					engine.stop_rendering = false
				}
			}
		}

		if (engine.stop_rendering) {
			time.sleep(time.Microsecond * 100)
			continue
		}

		if (engine.resize_requested) {
			log.info("Resizing swapchain")
			assert(resize_swapchain(engine) == nil, "Failed to resize swapchain")
		}

		imgui_vulkan.NewFrame()
		imgui_sdl2.NewFrame()
		imgui.NewFrame()

		if imgui.Begin("background") {
			defer imgui.End()

			imgui.SliderFloat("Render Scale", &engine.render_scale, 0.3, 1.)

			selected := &engine.backgroundEffects[engine.currentBackgroundEffect]

			imgui.Text("Selected effect: %s", selected.name)

			imgui.SliderInt(
				"Effect index",
				cast(^c.int)&engine.currentBackgroundEffect,
				0,
				cast(c.int)len(engine.backgroundEffects) - 1,
			)

			imgui.InputFloat4("data1", &selected.data.data1)
			imgui.InputFloat4("data2", &selected.data.data2)
			imgui.InputFloat4("data3", &selected.data.data3)
			imgui.InputFloat4("data4", &selected.data.data4)
		}

		imgui.ShowDemoWindow()

		imgui.Render()

		draw(engine)
	}
}

draw :: proc(engine: ^VulkanEngine) {
	vk_assert(
		vk.WaitForFences(
			engine.device.device,
			1,
			&get_current_frame(engine).render_fence,
			true,
			1000000000,
		),
	)

	assert(get_current_frame(engine) != nil)
	assert(engine.device != nil)
	assert(engine.swapchain != nil)

	swap_semaphore := get_current_frame(engine).swapchain_semaphore

	swapchainImageIndex: u32
	e := vk.AcquireNextImageKHR(
		engine.device.device,
		engine.swapchain.swapchain,
		1000000000,
		swap_semaphore,
		0,
		&swapchainImageIndex,
	)

	if e == .ERROR_OUT_OF_DATE_KHR {
		log.infof("Out of data nextimage: %s", e)
		engine.resize_requested = true
		return
	}

	assert(
		vk.ResetFences(engine.device.device, 1, &get_current_frame(engine).render_fence) ==
		.SUCCESS,
	)

	cmd := get_current_frame(engine).main_command_buffer

	vk_assert(vk.ResetCommandBuffer(cmd, {}))

	cmd_begin_info := command_buffer_begin_info({.ONE_TIME_SUBMIT})

	//engine.draw_extent.width = engine.draw_image.image_extent.width
	//engine.draw_extent.height = engine.draw_image.image_extent.height
	engine.draw_extent.height =
	cast(u32)(cast(f32)(min(
				engine.swapchain_extent.height,
				engine.draw_image.image_extent.height,
			)) *
		engine.render_scale)
	engine.draw_extent.width =
	cast(u32)(cast(f32)(min(engine.swapchain_extent.width, engine.draw_image.image_extent.width)) *
		engine.render_scale)


	vk_assert(vk.BeginCommandBuffer(cmd, &cmd_begin_info))

	transition_image(cmd, engine.draw_image.image, .UNDEFINED, .GENERAL)

	draw_background(engine, cmd)

	transition_image(cmd, engine.draw_image.image, .GENERAL, .COLOR_ATTACHMENT_OPTIMAL)
	transition_image(cmd, engine.depth_image.image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL)

	draw_geometry(engine, cmd)

	//transition the draw image and the swapchain image into their correct transfer layouts
	transition_image(
		cmd,
		engine.draw_image.image,
		.COLOR_ATTACHMENT_OPTIMAL,
		.TRANSFER_SRC_OPTIMAL,
	)
	transition_image(
		cmd,
		engine.swapchain_images[swapchainImageIndex],
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
	)

	// execute a copy from the draw image into the swapchain
	copy_image_to_image(
		cmd,
		engine.draw_image.image,
		engine.swapchain_images[swapchainImageIndex],
		engine.draw_extent,
		engine.swapchain_extent,
	)

	transition_image(
		cmd,
		engine.swapchain_images[swapchainImageIndex],
		.TRANSFER_DST_OPTIMAL,
		.COLOR_ATTACHMENT_OPTIMAL,
	)

	draw_imgui(engine, cmd, engine.swapchain_image_views[swapchainImageIndex])

	transition_image(
		cmd,
		engine.swapchain_images[swapchainImageIndex],
		.COLOR_ATTACHMENT_OPTIMAL,
		.PRESENT_SRC_KHR,
	)

	vk_assert(vk.EndCommandBuffer(cmd))

	cmd_info := command_buffer_submit_info(cmd)
	wait_info := semaphore_submit_info(
		{.COLOR_ATTACHMENT_OUTPUT_KHR},
		get_current_frame(engine).swapchain_semaphore,
	)
	signal_info := semaphore_submit_info(
		{.ALL_GRAPHICS},
		engine.render_semaphores[swapchainImageIndex],
	)

	submit := submit_info(&cmd_info, &signal_info, &wait_info)

	vk_assert(
		vk.QueueSubmit2(engine.graphics_queue, 1, &submit, get_current_frame(engine).render_fence),
	)

	presentInfo := vk.PresentInfoKHR{}
	presentInfo.sType = .PRESENT_INFO_KHR
	presentInfo.pNext = nil
	presentInfo.pSwapchains = &engine.swapchain.swapchain
	presentInfo.swapchainCount = 1

	presentInfo.pWaitSemaphores = &engine.render_semaphores[swapchainImageIndex]
	presentInfo.waitSemaphoreCount = 1

	presentInfo.pImageIndices = &swapchainImageIndex

	presentResult := vk.QueuePresentKHR(engine.graphics_queue, &presentInfo)
	if presentResult == .ERROR_OUT_OF_DATE_KHR || presentResult == .SUBOPTIMAL_KHR {
		log.info("Out of data present")
		engine.resize_requested = true
	}

	//increase the number of frames drawn
	engine.frame_number += 1
}

draw_imgui :: proc(engine: ^VulkanEngine, cmd: vk.CommandBuffer, targetImageView: vk.ImageView) {
	colorAttachment := attachment_info(targetImageView, nil)
	renderInfo := rendering_info(engine.swapchain_extent, &colorAttachment, nil)

	vk.CmdBeginRendering(cmd, &renderInfo)

	imgui_vulkan.RenderDrawData(imgui.GetDrawData(), cmd)

	vk.CmdEndRendering(cmd)
}

cleanup :: proc(engine: ^VulkanEngine) {
	vk.DeviceWaitIdle(engine.device.device)

	#reverse for func in engine.deinitFuncs {
		func(engine)
	}
}

init_vulkan :: proc(engine: ^VulkanEngine) -> vkb.Error {
	builder := vkb.create_instance_builder()
	defer vkb.destroy_instance_builder(builder)

	builder.app_name = "Example Vulkan Application"
	builder.request_validation_layers = bEnableValidationLayers
	vkb.instance_builder_use_default_debug_messenger(builder)
	builder.required_api_version = vk.MAKE_VERSION(1, 3, 0)

	vkb_inst := vkb.instance_builder_build(builder) or_return

	engine.instance = vkb_inst
	append(
		&engine.deinitFuncs,
		proc(engine: ^VulkanEngine) {vkb.destroy_instance(engine.instance)},
	)

	assert(!!sdl2.Vulkan_CreateSurface(engine.window, engine.instance.instance, &engine.surface))
	append(&engine.deinitFuncs, proc(engine: ^VulkanEngine) {
		vk.DestroySurfaceKHR(engine.instance.instance, engine.surface, nil)
	})

	features := vk.PhysicalDeviceVulkan13Features {
		sType            = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		dynamicRendering = true,
		synchronization2 = true,
	}

	features12: vk.PhysicalDeviceVulkan12Features
	features12.sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES
	features12.bufferDeviceAddress = true
	features12.descriptorIndexing = true

	selector := vkb.create_physical_device_selector_with_surface(engine.instance, engine.surface)
	defer vkb.destroy_physical_device_selector(selector)

	vkb.physical_device_selector_set_minimum_version_values(selector, 1, 3)
	vkb.physical_device_selector_set_required_features_12(selector, features12)
	vkb.physical_device_selector_set_required_features_13(selector, features)
	vkb.physical_device_selector_set_surface(selector, engine.surface)

	physical_device := vkb.physical_device_selector_select(selector) or_return

	//defer vkb.destroy_physical_device(physical_device)
	fmt.printfln("Selected GPU: %s", physical_device.properties.deviceName)
	fmt.printfln(
		"Vulkan version: %d.%d.%d",
		physical_device.properties.apiVersion >> 22,
		(physical_device.properties.apiVersion >> 12) & 0x3FF,
		physical_device.properties.apiVersion & 0xFFF,
	)

	device_builder := vkb.create_device_builder(physical_device)
	defer vkb.destroy_device_builder(device_builder)

	engine.device = vkb.device_builder_build(device_builder) or_return

	append(&engine.deinitFuncs, proc(engine: ^VulkanEngine) {vkb.destroy_device(engine.device)})

	engine.graphics_queue = vkb.device_get_queue(engine.device, .Graphics) or_return

	engine.graphics_queue_family = vkb.device_get_queue_index(engine.device, .Graphics) or_return

	assert(physical_device != nil)
	assert(physical_device.physical_device != nil)
	allocator_info := vma.Allocator_Create_Info{}
	allocator_info.physical_device = physical_device.physical_device
	allocator_info.device = engine.device.device
	allocator_info.instance = engine.instance.instance
	allocator_info.flags = {.Buffer_Device_Address}


	// Provide Vulkan function pointers (critical!)
	vulkan_funcs := vma.create_vulkan_functions()

	// Link it in
	allocator_info.vulkan_functions = &vulkan_funcs

	vk_assert(vma.create_allocator(allocator_info, &engine.allocator))

	append(
		&engine.deinitFuncs,
		proc(engine: ^VulkanEngine) {vma.destroy_allocator(engine.allocator)},
	)

	return nil
}

init_swapchain :: proc(engine: ^VulkanEngine) -> vkb.Error {
	drawImageExtent: vk.Extent3D = {engine.window_extent.width, engine.window_extent.height, 1}

	//hardcoding the draw format to 32 bit float
	engine.draw_image.image_format = .R16G16B16A16_SFLOAT
	engine.draw_image.image_extent = drawImageExtent

	drawImageUsages := vk.ImageUsageFlags{}
	drawImageUsages |= {.TRANSFER_SRC}
	drawImageUsages |= {.TRANSFER_DST}
	drawImageUsages |= {.STORAGE}
	drawImageUsages |= {.COLOR_ATTACHMENT}

	rimg_info := image_create_info(
		engine.draw_image.image_format,
		drawImageUsages,
		drawImageExtent,
	)

	//for the draw image, we want to allocate it from gpu local memory
	rimg_allocinfo := vma.Allocation_Create_Info{}
	rimg_allocinfo.usage = .Gpu_Only
	rimg_allocinfo.required_flags = {.DEVICE_LOCAL}

	//allocate and create the image
	vma.create_image(
		engine.allocator,
		rimg_info,
		rimg_allocinfo,
		&engine.draw_image.image,
		&engine.draw_image.allocation,
		nil,
	)

	//build a image-view for the draw image to use for rendering
	rview_info := imageview_create_info(
		engine.draw_image.image_format,
		engine.draw_image.image,
		{.COLOR},
	)

	vkb.vk_check(
		vk.CreateImageView(engine.device.device, &rview_info, nil, &engine.draw_image.image_view),
	) or_return

	append(&engine.deinitFuncs, proc(engine: ^VulkanEngine) {
		vk.DestroyImageView(engine.device.device, engine.draw_image.image_view, nil)
		vma.destroy_image(engine.allocator, engine.draw_image.image, engine.draw_image.allocation)
	})

	engine.depth_image.image_format = .D32_SFLOAT
	engine.depth_image.image_extent = drawImageExtent
	depthImageUsages: vk.ImageUsageFlags = {.DEPTH_STENCIL_ATTACHMENT}

	dimg_info := image_create_info(
		engine.depth_image.image_format,
		depthImageUsages,
		drawImageExtent,
	)

	//allocate and create the image
	vma.create_image(
		engine.allocator,
		dimg_info,
		rimg_allocinfo,
		&engine.depth_image.image,
		&engine.depth_image.allocation,
		nil,
	)

	//build a image-view for the draw image to use for rendering
	dview_info := imageview_create_info(
		engine.depth_image.image_format,
		engine.depth_image.image,
		{.DEPTH},
	)

	vkb.vk_check(
		vk.CreateImageView(engine.device.device, &dview_info, nil, &engine.depth_image.image_view),
	) or_return

	append(&engine.deinitFuncs, proc(engine: ^VulkanEngine) {
		vk.DestroyImageView(engine.device.device, engine.depth_image.image_view, nil)
		vma.destroy_image(
			engine.allocator,
			engine.depth_image.image,
			engine.depth_image.allocation,
		)
	})

	//add to deletion queues
	//_mainDeletionQueue.push_function([=]() {
	//	vkDestroyImageView(_device, _drawImage.imageView, nullptr);
	//	vmaDestroyImage(_allocator, _drawImage.image, _drawImage.allocation);

	create_swapchain(engine, engine.window_extent.width, engine.window_extent.height) or_return

	append(&engine.deinitFuncs, proc(engine: ^VulkanEngine) {
		destroy_swapchain(engine)
	})

	return nil
}

create_swapchain :: proc(engine: ^VulkanEngine, width: u32, height: u32) -> vkb.Error {
	swapchain_builder := vkb.create_swapchain_builder_default(engine.device)
	defer vkb.destroy_swapchain_builder(swapchain_builder)

	vkb.swapchain_builder_set_desired_format(
		swapchain_builder,
		vk.SurfaceFormatKHR {
			format     = .R8G8B8A8_UNORM, //
			colorSpace = .SRGB_NONLINEAR,
		},
	)
	vkb.swapchain_builder_set_desired_present_mode(swapchain_builder, .FIFO)
	vkb.swapchain_builder_set_desired_extent(swapchain_builder, width, height)
	vkb.swapchain_builder_add_image_usage_flags(
		swapchain_builder,
		vk.ImageUsageFlags{.TRANSFER_DST},
	)

	err: vkb.Error
	engine.swapchain = vkb.swapchain_builder_build(swapchain_builder) or_return

	engine.swapchain_extent = engine.swapchain.extent

	engine.swapchain_images, err = vkb.swapchain_get_images(engine.swapchain)

	engine.swapchain_image_views = vkb.swapchain_get_image_views(engine.swapchain) or_return

	return nil
}

destroy_swapchain :: proc(engine: ^VulkanEngine) {
	vkb.destroy_swapchain(engine.swapchain)

	vkb.swapchain_destroy_image_views(engine.swapchain, engine.swapchain_image_views)
	delete(engine.swapchain_image_views)
}

get_current_frame :: proc(engine: ^VulkanEngine) -> ^FrameData {
	return &engine.frames[engine.frame_number % FRAME_OVERLAP]
}

init_commands :: proc(engine: ^VulkanEngine) -> vk.Result {
	err: vk.Result = .SUCCESS

	command_pool_info := command_pool_create_info(
		engine.graphics_queue_family,
		flags = {.RESET_COMMAND_BUFFER},
	)

	{
		vk.CreateCommandPool(
			engine.device.device,
			&command_pool_info,
			nil,
			&engine.imm_command_pool,
		) or_return

		cmdAllocInfo := command_buffer_alloc_info(engine.imm_command_pool)

		vk.AllocateCommandBuffers(
			engine.device.device,
			&cmdAllocInfo,
			&engine.imm_command_buffer,
		) or_return

		append(&engine.deinitFuncs, proc(engine: ^VulkanEngine) {
			vk.DestroyCommandPool(engine.device.device, engine.imm_command_pool, nil)
		})
	}

	for i := 0; i < FRAME_OVERLAP; i += 1 {
		vk.CreateCommandPool(
			engine.device.device,
			&command_pool_info,
			nil,
			&engine.frames[i].command_pool,
		) or_return

		cmd_alloc_info := command_buffer_alloc_info(engine.frames[i].command_pool)

		vk.AllocateCommandBuffers(
			engine.device.device,
			&cmd_alloc_info,
			&engine.frames[i].main_command_buffer,
		) or_return
	}

	append(&engine.deinitFuncs, proc(engine: ^VulkanEngine) {
		for &frame in engine.frames {
			vk.FreeCommandBuffers(
				engine.device.device,
				frame.command_pool,
				1,
				&frame.main_command_buffer,
			)
			vk.DestroyCommandPool(engine.device.device, frame.command_pool, nil)
		}
	})

	append(
		&engine.deinitFuncs,
		proc(engine: ^VulkanEngine) {vk.DeviceWaitIdle(engine.device.device)},
	)

	return nil
}

command_pool_create_info :: proc(
	queueFamilyIndex: u32,
	flags: vk.CommandPoolCreateFlags = {},
) -> vk.CommandPoolCreateInfo {
	info: vk.CommandPoolCreateInfo
	info.sType = .COMMAND_POOL_CREATE_INFO
	info.pNext = nil
	info.queueFamilyIndex = queueFamilyIndex
	info.flags = flags

	return info
}

command_buffer_alloc_info :: proc(
	pool: vk.CommandPool,
	count: u32 = 1,
	level: vk.CommandBufferLevel = .PRIMARY,
) -> vk.CommandBufferAllocateInfo {
	info: vk.CommandBufferAllocateInfo
	info.sType = .COMMAND_BUFFER_ALLOCATE_INFO
	info.pNext = nil

	info.commandPool = pool
	info.commandBufferCount = count
	info.level = level

	return info
}

fence_create_info :: proc(flags: vk.FenceCreateFlags = {}) -> vk.FenceCreateInfo {
	info: vk.FenceCreateInfo = {}
	info.sType = .FENCE_CREATE_INFO
	info.pNext = nil

	info.flags = flags

	return info
}

semaphore_create_info :: proc(flags: vk.SemaphoreCreateFlags = {}) -> vk.SemaphoreCreateInfo {
	info: vk.SemaphoreCreateInfo = {}
	info.sType = .SEMAPHORE_CREATE_INFO
	info.pNext = nil
	info.flags = flags
	return info
}

init_sync_structures :: proc(engine: ^VulkanEngine) -> vk.Result {
	fence_create_info := fence_create_info({.SIGNALED})
	semaphore_create_info := semaphore_create_info()

	res: vk.Result = .SUCCESS

	vk.CreateFence(engine.device.device, &fence_create_info, nil, &engine.imm_fence) or_return
	append(&engine.deinitFuncs, proc(engine: ^VulkanEngine) {
		vk.DestroyFence(engine.device.device, engine.imm_fence, nil)
	})

	for &frame in engine.frames {
		res = vk.CreateFence(engine.device.device, &fence_create_info, nil, &frame.render_fence)
		if (res != .SUCCESS) {
			return res
		}
		res = vk.CreateSemaphore(
			engine.device.device,
			&semaphore_create_info,
			nil,
			&frame.swapchain_semaphore,
		)
		if (res != .SUCCESS) {
			return res
		}
	}

	engine.render_semaphores = make([]vk.Semaphore, len(engine.swapchain_images))

	for i := 0; i < len(engine.swapchain_images); i += 1 {
		res = vk.CreateSemaphore(
			engine.device.device,
			&semaphore_create_info,
			nil,
			&engine.render_semaphores[i],
		)
		if (res != .SUCCESS) {
			return res
		}
	}

	append(&engine.deinitFuncs, proc(engine: ^VulkanEngine) {
		vk.DeviceWaitIdle(engine.device.device)

		for &frame in engine.frames {
			vk.DestroyFence(engine.device.device, frame.render_fence, nil)
			vk.DestroySemaphore(engine.device.device, frame.swapchain_semaphore, nil)
		}

		for render_semaphore in engine.render_semaphores {
			vk.DestroySemaphore(engine.device.device, render_semaphore, nil)
		}

		delete(engine.render_semaphores)
	})

	return res
}

vk_assert :: proc(res: vk.Result, loc := #caller_location) {
	buf: [1024]u8

	assert(
		res == .SUCCESS,
		message = fmt.bprintfln(buf[:], "Result not success: %s", res),
		loc = loc,
	)
}

command_buffer_begin_info :: proc(flags: vk.CommandBufferUsageFlags) -> vk.CommandBufferBeginInfo {
	info: vk.CommandBufferBeginInfo = {}

	info.sType = .COMMAND_BUFFER_BEGIN_INFO
	info.pNext = nil

	info.pInheritanceInfo = nil
	info.flags = flags

	return info
}

transition_image :: proc(
	cmd: vk.CommandBuffer,
	image: vk.Image,
	current_layout: vk.ImageLayout,
	new_layout: vk.ImageLayout,
) {
	image_barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
		pNext = nil,
	}

	image_barrier.srcStageMask = {.ALL_COMMANDS}
	image_barrier.srcAccessMask = {.MEMORY_WRITE}
	image_barrier.dstStageMask = {.ALL_COMMANDS}
	image_barrier.dstAccessMask = {.MEMORY_WRITE, .MEMORY_READ}

	image_barrier.oldLayout = current_layout
	image_barrier.newLayout = new_layout

	aspectMask: vk.ImageAspectFlags =
		(new_layout == .DEPTH_ATTACHMENT_OPTIMAL) ? {.DEPTH} : {.COLOR}
	image_barrier.subresourceRange = image_subresource_range(aspectMask)
	image_barrier.image = image

	dep_info: vk.DependencyInfo = {}
	dep_info.sType = .DEPENDENCY_INFO
	dep_info.pNext = nil

	dep_info.imageMemoryBarrierCount = 1
	dep_info.pImageMemoryBarriers = &image_barrier

	vk.CmdPipelineBarrier2(cmd, &dep_info)
}

image_subresource_range :: proc(aspectMask: vk.ImageAspectFlags) -> vk.ImageSubresourceRange {
	subImage: vk.ImageSubresourceRange = {}
	subImage.aspectMask = aspectMask
	subImage.baseMipLevel = 0
	subImage.levelCount = vk.REMAINING_MIP_LEVELS
	subImage.baseArrayLayer = 0
	subImage.layerCount = vk.REMAINING_ARRAY_LAYERS

	return subImage
}

semaphore_submit_info :: proc(
	stageMask: vk.PipelineStageFlags2,
	semaphore: vk.Semaphore,
) -> vk.SemaphoreSubmitInfo {
	submitInfo := vk.SemaphoreSubmitInfo{}
	submitInfo.sType = .SEMAPHORE_SUBMIT_INFO
	submitInfo.pNext = nil
	submitInfo.semaphore = semaphore
	submitInfo.stageMask = stageMask
	submitInfo.deviceIndex = 0
	submitInfo.value = 1

	return submitInfo
}

command_buffer_submit_info :: proc(cmd: vk.CommandBuffer) -> vk.CommandBufferSubmitInfo {
	info := vk.CommandBufferSubmitInfo{}
	info.sType = .COMMAND_BUFFER_SUBMIT_INFO
	info.pNext = nil
	info.commandBuffer = cmd
	info.deviceMask = 0

	return info
}

submit_info :: proc(
	cmd: ^vk.CommandBufferSubmitInfo,
	signalSemaphoreInfo: ^vk.SemaphoreSubmitInfo = nil,
	waitSemaphoreInfo: ^vk.SemaphoreSubmitInfo = nil,
) -> vk.SubmitInfo2 {
	info := vk.SubmitInfo2{}
	info.sType = .SUBMIT_INFO_2
	info.pNext = nil

	info.waitSemaphoreInfoCount = waitSemaphoreInfo == nil ? 0 : 1
	info.pWaitSemaphoreInfos = waitSemaphoreInfo

	info.signalSemaphoreInfoCount = signalSemaphoreInfo == nil ? 0 : 1
	info.pSignalSemaphoreInfos = signalSemaphoreInfo

	info.commandBufferInfoCount = 1
	info.pCommandBufferInfos = cmd

	return info
}

image_create_info :: proc(
	format: vk.Format,
	usageFlags: vk.ImageUsageFlags,
	extent: vk.Extent3D,
) -> vk.ImageCreateInfo {
	info := vk.ImageCreateInfo{}
	info.sType = .IMAGE_CREATE_INFO
	info.pNext = nil

	info.imageType = .D2

	info.format = format
	info.extent = extent

	info.mipLevels = 1
	info.arrayLayers = 1

	//for MSAA. we will not be using it by default, so default it to 1 sample per pixel.
	info.samples = {._1}

	//optimal tiling, which means the image is stored on the best gpu format
	info.tiling = .OPTIMAL
	info.usage = usageFlags

	return info
}

imageview_create_info :: proc(
	format: vk.Format,
	image: vk.Image,
	aspectFlags: vk.ImageAspectFlags,
) -> vk.ImageViewCreateInfo {
	// build a image-view for the depth image to use for rendering
	info: vk.ImageViewCreateInfo = {}
	info.sType = .IMAGE_VIEW_CREATE_INFO
	info.pNext = nil

	info.viewType = .D2
	info.image = image
	info.format = format
	info.subresourceRange.baseMipLevel = 0
	info.subresourceRange.levelCount = 1
	info.subresourceRange.baseArrayLayer = 0
	info.subresourceRange.layerCount = 1
	info.subresourceRange.aspectMask = aspectFlags

	return info
}

copy_image_to_image :: proc(
	cmd: vk.CommandBuffer,
	source: vk.Image,
	dest: vk.Image,
	src_size: vk.Extent2D,
	dst_size: vk.Extent2D,
) {
	blit_region := vk.ImageBlit2 {
		sType = .IMAGE_BLIT_2,
		pNext = nil,
	}

	blit_region.srcOffsets[1].x = cast(i32)src_size.width
	blit_region.srcOffsets[1].y = cast(i32)src_size.height
	blit_region.srcOffsets[1].z = 1

	blit_region.dstOffsets[1].x = cast(i32)dst_size.width
	blit_region.dstOffsets[1].y = cast(i32)dst_size.height
	blit_region.dstOffsets[1].z = 1

	blit_region.srcSubresource.aspectMask = {.COLOR}
	blit_region.srcSubresource.baseArrayLayer = 0
	blit_region.srcSubresource.layerCount = 1
	blit_region.srcSubresource.mipLevel = 0

	blit_region.dstSubresource.aspectMask = {.COLOR}
	blit_region.dstSubresource.baseArrayLayer = 0
	blit_region.dstSubresource.layerCount = 1
	blit_region.dstSubresource.mipLevel = 0

	blitInfo := vk.BlitImageInfo2 {
		sType = .BLIT_IMAGE_INFO_2,
		pNext = nil,
	}
	blitInfo.dstImage = dest
	blitInfo.dstImageLayout = .TRANSFER_DST_OPTIMAL
	blitInfo.srcImage = source
	blitInfo.srcImageLayout = .TRANSFER_SRC_OPTIMAL
	blitInfo.filter = .LINEAR
	blitInfo.regionCount = 1
	blitInfo.pRegions = &blit_region

	vk.CmdBlitImage2(cmd, &blitInfo)
}

draw_background :: proc(engine: ^VulkanEngine, cmd: vk.CommandBuffer) {
	effect := &engine.backgroundEffects[engine.currentBackgroundEffect]

	vk.CmdBindPipeline(cmd, .COMPUTE, effect.pipeline)

	vk.CmdBindDescriptorSets(
		cmd,
		.COMPUTE,
		engine.gradient_pipeline_layout,
		0,
		1,
		&engine.draw_image_descriptors,
		0,
		nil,
	)

	vk.CmdPushConstants(
		cmd,
		engine.gradient_pipeline_layout,
		{.COMPUTE},
		0,
		size_of(ComputePushConstants),
		&effect.data,
	)

	vk.CmdDispatch(
		cmd,
		cast(u32)math.ceil((cast(f32)engine.draw_extent.width) / 16.0),
		cast(u32)math.ceil((cast(f32)engine.draw_extent.height) / 16.0),
		1,
	)
}

init_descriptors :: proc(engine: ^VulkanEngine) -> vkb.Error {
	sizes := [?]PoolSizeRatio{PoolSizeRatio{type = .STORAGE_IMAGE, ratio = 1.0}}

	descriptor_allocator_init_pool(
		&engine.global_descriptor_allocator,
		engine.device.device,
		10,
		sizes[:],
	)

	{
		builder := DescriptorLayoutBuilder{}
		descriptor_builder_add_binding(&builder, 0, .STORAGE_IMAGE)
		engine.draw_image_descriptor_layout = descriptor_builder_build(
			&builder,
			engine.device.device,
			{.COMPUTE},
		) or_return
	}

	engine.draw_image_descriptors = descriptor_allocator_allocate(
		&engine.global_descriptor_allocator,
		engine.device.device,
		engine.draw_image_descriptor_layout,
	)

	img_info := vk.DescriptorImageInfo{}
	img_info.imageLayout = .GENERAL
	img_info.imageView = engine.draw_image.image_view

	draw_image_write := vk.WriteDescriptorSet {
		sType = .WRITE_DESCRIPTOR_SET,
		pNext = nil,
	}

	draw_image_write.dstBinding = 0
	draw_image_write.dstSet = engine.draw_image_descriptors
	draw_image_write.descriptorCount = 1
	draw_image_write.descriptorType = .STORAGE_IMAGE
	draw_image_write.pImageInfo = &img_info

	vk.UpdateDescriptorSets(engine.device.device, 1, &draw_image_write, 0, nil)

	append(&engine.deinitFuncs, proc(engine: ^VulkanEngine) {
		descriptor_allocator_destroy_pool(
			&engine.global_descriptor_allocator,
			engine.device.device,
		)
		vk.DestroyDescriptorSetLayout(
			engine.device.device,
			engine.draw_image_descriptor_layout,
			nil,
		)
	})

	return nil
}

init_pipelines :: proc(engine: ^VulkanEngine) {
	err := init_background_pipelines(engine)
	if err != nil {
		fmt.panicf("Failed to create pipeline: %e", err)
	}

	vk_err := init_mesh_pipeline(engine)
	if vk_err != .SUCCESS {
		fmt.panicf("Failed to create pipeline: %e", vk_err)
	}
}

init_background_pipelines :: proc(engine: ^VulkanEngine) -> LoadShaderError {
	compute_layout := vk.PipelineLayoutCreateInfo {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
		pNext = nil,
	}

	compute_layout.pSetLayouts = &engine.draw_image_descriptor_layout
	compute_layout.setLayoutCount = 1

	pushConstant: vk.PushConstantRange
	pushConstant.offset = 0
	pushConstant.size = size_of(ComputePushConstants)
	pushConstant.stageFlags = {.COMPUTE}

	compute_layout.pPushConstantRanges = &pushConstant
	compute_layout.pushConstantRangeCount = 1

	vkb.vk_check(
		vk.CreatePipelineLayout(
			engine.device.device,
			&compute_layout,
			nil,
			&engine.gradient_pipeline_layout,
		),
	) or_return

	append(&engine.deinitFuncs, proc(engine: ^VulkanEngine) {
		vk.DestroyPipelineLayout(engine.device.device, engine.gradient_pipeline_layout, nil)
	})

	gradient_shader := load_shader_module(
		"shaders/gradient_color.comp.spv",
		engine.device.device,
	) or_return

	defer vk.DestroyShaderModule(engine.device.device, gradient_shader, nil)

	sky_shader := load_shader_module("shaders/sky.comp.spv", engine.device.device) or_return

	defer vk.DestroyShaderModule(engine.device.device, sky_shader, nil)

	stageinfo: vk.PipelineShaderStageCreateInfo
	stageinfo.sType = .PIPELINE_SHADER_STAGE_CREATE_INFO
	stageinfo.pNext = nil
	stageinfo.stage = {.COMPUTE}
	stageinfo.module = gradient_shader
	stageinfo.pName = "main"

	computePipelineCreateInfo: vk.ComputePipelineCreateInfo
	computePipelineCreateInfo.sType = .COMPUTE_PIPELINE_CREATE_INFO
	computePipelineCreateInfo.pNext = nil
	computePipelineCreateInfo.layout = engine.gradient_pipeline_layout
	computePipelineCreateInfo.stage = stageinfo

	gradient: ComputeEffect
	gradient.layout = engine.gradient_pipeline_layout
	gradient.name = "gradient"
	gradient.data = {}

	gradient.data.data1 = {1, 0, 0, 1}
	gradient.data.data2 = {0, 0, 1, 1}

	vkb.vk_check(
		vk.CreateComputePipelines(
			engine.device.device,
			0,
			1,
			&computePipelineCreateInfo,
			nil,
			&gradient.pipeline,
		),
	) or_return

	computePipelineCreateInfo.stage.module = sky_shader

	sky: ComputeEffect
	sky.layout = engine.gradient_pipeline_layout
	sky.name = "sky"
	sky.data = {}

	sky.data.data1 = {0.1, 0.2, 0.4, 0.97}

	vkb.vk_check(
		vk.CreateComputePipelines(
			engine.device.device,
			0,
			1,
			&computePipelineCreateInfo,
			nil,
			&sky.pipeline,
		),
	) or_return

	append(&engine.backgroundEffects, gradient)
	append(&engine.backgroundEffects, sky)

	fmt.println("Created gradient_pipeline")

	append(&engine.deinitFuncs, proc(engine: ^VulkanEngine) {
		for effect in engine.backgroundEffects {
			vk.DestroyPipeline(engine.device.device, effect.pipeline, nil)
		}
	})

	return nil
}

@(private)
init_imgui :: proc(engine: ^VulkanEngine) -> vk.Result {
	pool_sizes := [?]vk.DescriptorPoolSize {
		{type = .SAMPLER, descriptorCount = 1000},
		{type = .COMBINED_IMAGE_SAMPLER, descriptorCount = 1000},
		{type = .SAMPLED_IMAGE, descriptorCount = 1000},
		{type = .STORAGE_IMAGE, descriptorCount = 1000},
		{type = .UNIFORM_TEXEL_BUFFER, descriptorCount = 1000},
		{type = .STORAGE_TEXEL_BUFFER, descriptorCount = 1000},
		{type = .UNIFORM_BUFFER, descriptorCount = 1000},
		{type = .STORAGE_BUFFER, descriptorCount = 1000},
		{type = .UNIFORM_BUFFER_DYNAMIC, descriptorCount = 1000},
		{type = .STORAGE_BUFFER_DYNAMIC, descriptorCount = 1000},
		{type = .INPUT_ATTACHMENT, descriptorCount = 1000},
	}

	pool_info: vk.DescriptorPoolCreateInfo
	pool_info.sType = .DESCRIPTOR_POOL_CREATE_INFO
	pool_info.flags = {.FREE_DESCRIPTOR_SET}
	pool_info.maxSets = 1000
	pool_info.poolSizeCount = len(pool_sizes)
	pool_info.pPoolSizes = raw_data(pool_sizes[:])

	vk.CreateDescriptorPool(engine.device.device, &pool_info, nil, &engine.imgui_pool) or_return

	imgui.CHECKVERSION()
	imgui.CreateContext()

	assert(imgui_sdl2.InitForVulkan(engine.window))

	assert(
		imgui_vulkan.LoadFunctions(
			proc "c" (name: cstring, user_data: rawptr) -> vk.ProcVoidFunction {
				return vk.GetInstanceProcAddr((^vk.Instance)(user_data)^, name)
			},
			&engine.instance.instance,
		),
		"Failed to load imgui Vulkan functions",
	)

	init_info: imgui_vulkan.InitInfo
	init_info.Instance = engine.instance.instance
	init_info.PhysicalDevice = engine.device.physical_device.physical_device
	init_info.Device = engine.device.device
	init_info.Queue = engine.graphics_queue
	init_info.DescriptorPool = engine.imgui_pool
	init_info.MinImageCount = 3
	init_info.ImageCount = 3
	init_info.UseDynamicRendering = true

	init_info.PipelineRenderingCreateInfo.sType = .PIPELINE_RENDERING_CREATE_INFO
	init_info.PipelineRenderingCreateInfo.colorAttachmentCount = 1
	init_info.PipelineRenderingCreateInfo.pColorAttachmentFormats = &engine.swapchain.image_format

	init_info.MSAASamples = ._1

	assert(imgui_vulkan.Init(&init_info))

	assert(imgui_vulkan.CreateFontsTexture())

	append(&engine.deinitFuncs, proc(engine: ^VulkanEngine) {
		imgui_vulkan.Shutdown()
		vk.DestroyDescriptorPool(engine.device.device, engine.imgui_pool, nil)
	})

	return nil
}

immediate_start :: proc(engine: ^VulkanEngine) -> (cmd: vk.CommandBuffer, err: vk.Result) {
	vk.ResetFences(engine.device.device, 1, &engine.imm_fence) or_return
	vk.ResetCommandBuffer(engine.imm_command_buffer, {}) or_return

	cmd = engine.imm_command_buffer

	cmd_begin_info := command_buffer_begin_info({.ONE_TIME_SUBMIT})

	vk.BeginCommandBuffer(cmd, &cmd_begin_info) or_return

	return
}

immediate_submit :: proc(engine: ^VulkanEngine, cmd: vk.CommandBuffer) -> vk.Result {
	vk.EndCommandBuffer(cmd) or_return

	cmd_info := command_buffer_submit_info(cmd)

	submit := submit_info(&cmd_info)

	vk.QueueSubmit2(engine.graphics_queue, 1, &submit, engine.imm_fence) or_return

	vk.WaitForFences(engine.device.device, 1, &engine.imm_fence, true, 99999999) or_return

	return nil
}

attachment_info :: proc(
	view: vk.ImageView,
	clear: ^vk.ClearValue,
	layout: vk.ImageLayout = .COLOR_ATTACHMENT_OPTIMAL,
) -> vk.RenderingAttachmentInfo {
	colorAttachment: vk.RenderingAttachmentInfo
	colorAttachment.sType = .RENDERING_ATTACHMENT_INFO
	colorAttachment.pNext = nil

	colorAttachment.imageView = view
	colorAttachment.imageLayout = layout
	colorAttachment.loadOp = clear != nil ? .CLEAR : .LOAD
	colorAttachment.storeOp = .STORE
	if (clear != nil) {
		colorAttachment.clearValue = clear^
	}

	return colorAttachment
}

depth_attachment_info :: proc(
	view: vk.ImageView,
	layout: vk.ImageLayout = .COLOR_ATTACHMENT_OPTIMAL,
) -> vk.RenderingAttachmentInfo {
	depthAttachment: vk.RenderingAttachmentInfo = {}
	depthAttachment.sType = .RENDERING_ATTACHMENT_INFO
	depthAttachment.pNext = nil

	depthAttachment.imageView = view
	depthAttachment.imageLayout = layout
	depthAttachment.loadOp = .CLEAR
	depthAttachment.storeOp = .STORE
	depthAttachment.clearValue.depthStencil.depth = 0.0

	return depthAttachment
}

rendering_info :: proc(
	renderExtent: vk.Extent2D,
	colorAttachment: ^vk.RenderingAttachmentInfo,
	depthAttachment: ^vk.RenderingAttachmentInfo,
) -> vk.RenderingInfo {
	renderInfo: vk.RenderingInfo
	renderInfo.sType = .RENDERING_INFO
	renderInfo.pNext = nil

	renderInfo.renderArea = vk.Rect2D{vk.Offset2D{0, 0}, renderExtent}
	renderInfo.layerCount = 1
	renderInfo.colorAttachmentCount = 1
	renderInfo.pColorAttachments = colorAttachment
	renderInfo.pDepthAttachment = depthAttachment
	renderInfo.pStencilAttachment = nil

	return renderInfo
}

draw_geometry :: proc(engine: ^VulkanEngine, cmd: vk.CommandBuffer) {
	colorAttachment := attachment_info(
		engine.draw_image.image_view,
		nil,
		.COLOR_ATTACHMENT_OPTIMAL,
	)
	depthAttachment := depth_attachment_info(
		engine.depth_image.image_view,
		.DEPTH_ATTACHMENT_OPTIMAL,
	)

	renderInfo := rendering_info(engine.draw_extent, &colorAttachment, &depthAttachment)

	vk.CmdBeginRendering(cmd, &renderInfo)
	defer vk.CmdEndRendering(cmd)

	vk.CmdBindPipeline(cmd, .GRAPHICS, engine.meshPipeline)

	viewport: vk.Viewport = {}
	viewport.x = 0
	viewport.y = 0
	viewport.width = cast(f32)engine.draw_extent.width
	viewport.height = cast(f32)engine.draw_extent.height
	viewport.minDepth = 0.
	viewport.maxDepth = 1.

	vk.CmdSetViewport(cmd, 0, 1, &viewport)

	scissor: vk.Rect2D = {}
	scissor.offset.x = 0
	scissor.offset.y = 0
	scissor.extent.width = engine.draw_extent.width
	scissor.extent.height = engine.draw_extent.height

	vk.CmdSetScissor(cmd, 0, 1, &scissor)


	push_constants: GPUDrawPushConstants
	push_constants.worldMatrix = 1.

	projection := linalg.matrix4_perspective(
		math.to_radians_f32(70.),
		f32(engine.draw_extent.width) / f32(engine.draw_extent.height),
		10000., // near
		0.1, // far
		true,
	)

	view := linalg.matrix4_look_at_f32({0, 0, -5}, {0, 0, 0}, {0, 1, 0})

	model := linalg.transpose(linalg.matrix4_scale_f32(1))

	push_constants.worldMatrix = linalg.transpose(projection * view * model) // * model
	push_constants.worldMatrix[1][1] *= -1
	push_constants.vertexBuffer = engine.testMeshes[2].meshBuffers.vertexBufferAddress

	vk.CmdPushConstants(
		cmd,
		engine.meshPipelineLayout,
		{.VERTEX},
		0,
		size_of(GPUDrawPushConstants),
		&push_constants,
	)

	vk.CmdBindIndexBuffer(cmd, engine.testMeshes[2].meshBuffers.indexBuffer.buffer, 0, .UINT32)

	vk.CmdDrawIndexed(
		cmd,
		engine.testMeshes[2].surfaces[0].count,
		1,
		engine.testMeshes[2].surfaces[0].startIndex,
		0,
		0,
	)
}

create_buffer :: proc(
	engine: ^VulkanEngine,
	allocSize: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	memoryUsage: vma.Memory_Usage,
) -> (
	buffer: AllocatedBuffer,
	err: vk.Result,
) {
	bufferInfo: vk.BufferCreateInfo = {
		sType = .BUFFER_CREATE_INFO,
	}

	bufferInfo.pNext = nil
	bufferInfo.size = allocSize

	bufferInfo.usage = usage

	vmaAllocInfo: vma.Allocation_Create_Info
	vmaAllocInfo.usage = memoryUsage
	vmaAllocInfo.flags = {.Mapped}

	vma.create_buffer(
		engine.allocator,
		bufferInfo,
		vmaAllocInfo,
		&buffer.buffer,
		&buffer.allocation,
		&buffer.info,
	) or_return

	return
}

destroy_buffer :: proc(engine: ^VulkanEngine, #by_ptr buffer: AllocatedBuffer) {
	vma.destroy_buffer(engine.allocator, buffer.buffer, buffer.allocation)
}

uploadMesh :: proc(
	engine: ^VulkanEngine,
	indices: []u32,
	vertices: []Vertex,
) -> (
	buffer: GPUMeshBuffers,
	err: vk.Result,
) {
	vertexBufferSize := cast(vk.DeviceSize)(len(vertices) * size_of(Vertex))
	indexBufferSize := cast(vk.DeviceSize)(len(indices) * size_of(u32))

	newSurface: GPUMeshBuffers

	newSurface.vertexBuffer = create_buffer(
		engine,
		vertexBufferSize,
		{.STORAGE_BUFFER, .TRANSFER_DST, .SHADER_DEVICE_ADDRESS},
		.Gpu_Only,
	) or_return

	deviceAdressInfo: vk.BufferDeviceAddressInfo = {
		sType  = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = newSurface.vertexBuffer.buffer,
	}
	newSurface.vertexBufferAddress = vk.GetBufferDeviceAddress(
		engine.device.device,
		&deviceAdressInfo,
	)

	newSurface.indexBuffer = create_buffer(
		engine,
		indexBufferSize,
		{.INDEX_BUFFER, .TRANSFER_DST},
		.Gpu_Only,
	) or_return

	staging := create_buffer(
		engine,
		vertexBufferSize + indexBufferSize,
		{.TRANSFER_SRC},
		.Cpu_Only,
	) or_return
	defer destroy_buffer(engine, staging)

	data: rawptr = ---

	vma.map_memory(engine.allocator, staging.allocation, &data)
	defer vma.unmap_memory(engine.allocator, staging.allocation)

	mem.copy(data, raw_data(vertices), cast(int)vertexBufferSize)

	mem.copy(
		mem.ptr_offset(cast([^]u8)data, vertexBufferSize),
		raw_data(indices),
		cast(int)indexBufferSize,
	)

	UserData :: struct {
		staging:    AllocatedBuffer,
		newSurface: GPUMeshBuffers,
	}

	{
		cmd := immediate_start(engine) or_return

		vertexCopy: vk.BufferCopy = {}
		vertexCopy.dstOffset = 0
		vertexCopy.srcOffset = 0
		vertexCopy.size = vertexBufferSize

		vk.CmdCopyBuffer(cmd, staging.buffer, newSurface.vertexBuffer.buffer, 1, &vertexCopy)

		indexCopy: vk.BufferCopy = {}
		indexCopy.dstOffset = 0
		indexCopy.srcOffset = vertexBufferSize
		indexCopy.size = indexBufferSize

		vk.CmdCopyBuffer(cmd, staging.buffer, newSurface.indexBuffer.buffer, 1, &indexCopy)

		immediate_submit(engine, cmd) or_return
	}

	buffer = newSurface

	return
}

init_mesh_pipeline :: proc(engine: ^VulkanEngine) -> vk.Result {
	err: LoadShaderError = nil
	triangleFragShader: vk.ShaderModule
	triangleFragShader, err = load_shader_module(
		"shaders/color_triangle.frag.spv",
		engine.device.device,
	)
	if err == nil {
		log.info("Triangle fragment shader succesfully loaded")
	} else {
		log.errorf("Failed to load triangle fragment shader: %s", err)
	}
	defer vk.DestroyShaderModule(engine.device.device, triangleFragShader, nil)

	triangleVertexShader: vk.ShaderModule
	triangleVertexShader, err = load_shader_module(
		"shaders/color_triangle_mesh.vert.spv",
		engine.device.device,
	)
	if err == nil {
		log.info("Triangle vertex shader succesfully loaded")
	} else {
		log.errorf("Failed to load triangle vertex shader: %s", err)
	}
	defer vk.DestroyShaderModule(engine.device.device, triangleVertexShader, nil)

	bufferRange: vk.PushConstantRange = {}
	bufferRange.offset = 0
	bufferRange.size = size_of(GPUDrawPushConstants)
	bufferRange.stageFlags = {.VERTEX}

	pipeline_layout_info: vk.PipelineLayoutCreateInfo = pipeline_layout_create_info()
	pipeline_layout_info.pPushConstantRanges = &bufferRange
	pipeline_layout_info.pushConstantRangeCount = 1

	vk.CreatePipelineLayout(
		engine.device.device,
		&pipeline_layout_info,
		nil,
		&engine.meshPipelineLayout,
	) or_return
	append(&engine.deinitFuncs, proc(engine: ^VulkanEngine) {
		vk.DestroyPipelineLayout(engine.device.device, engine.meshPipelineLayout, nil)
	})

	pipelineBuilder: PipelineBuilder
	pipeline_builder_clear(&pipelineBuilder)

	//use the triangle layout we created
	pipelineBuilder.pipelineLayout = engine.meshPipelineLayout
	//connecting the vertex and pixel shaders to the pipeline
	pipeline_builder_set_shaders(&pipelineBuilder, triangleVertexShader, triangleFragShader)
	//it will draw triangles
	pipeline_builder_set_topology(&pipelineBuilder, .TRIANGLE_LIST)
	//filled triangles
	pipeline_builder_set_polygon_mode(&pipelineBuilder, .FILL)
	//no backface culling
	pipeline_builder_set_cull_mode(&pipelineBuilder, {}, .CLOCKWISE)
	//no multisampling
	pipeline_builder_set_multisampling_none(&pipelineBuilder)
	//no blending
	//pipeline_builder_disable_blending(&pipelineBuilder)
	pipeline_builder_enable_blending_additive(&pipelineBuilder)

	pipeline_builder_enable_depthtest(&pipelineBuilder, true, .GREATER_OR_EQUAL)

	//connect the image format we will draw into, from draw image
	pipeline_builder_set_color_attachment_format(&pipelineBuilder, engine.draw_image.image_format)
	pipeline_builder_set_depth_format(&pipelineBuilder, engine.depth_image.image_format)

	//finally build the pipeline
	engine.meshPipeline = pipeline_builder_build(&pipelineBuilder, engine.device.device) or_return
	append(&engine.deinitFuncs, proc(engine: ^VulkanEngine) {
		vk.DestroyPipeline(engine.device.device, engine.meshPipeline, nil)
	})

	return .SUCCESS
}

init_default_data :: proc(engine: ^VulkanEngine) -> vk.Result {
	ok: bool
	engine.testMeshes, ok = loadGltfMeshes(engine, "assets/basicmesh.glb")
	fmt.assertf(ok, "Failed to load meshes: %s", "assets/basicmesh.glb")
	append(&engine.deinitFuncs, proc(engine: ^VulkanEngine) {
		for mesh in engine.testMeshes {
			destroy_buffer(engine, mesh.meshBuffers.vertexBuffer)
			destroy_buffer(engine, mesh.meshBuffers.indexBuffer)
		}
	})

	return .SUCCESS
}

resize_swapchain :: proc(engine: ^VulkanEngine) -> vkb.Error {
	vkb.vk_check(vk.DeviceWaitIdle(engine.device.device)) or_return

	log.info("Destroying swapchain")

	destroy_swapchain(engine)

	log.info("Destroyed swapchain")

	w, h: c.int
	sdl2.GetWindowSize(engine.window, &w, &h)
	engine.window_extent.width = cast(u32)w
	engine.window_extent.height = cast(u32)h

	log.info("Creating swapchain")
	create_swapchain(engine, engine.window_extent.width, engine.window_extent.height) or_return

	engine.resize_requested = false

	return nil
}
