package engine

import vk "vendor:vulkan"

import vkb "../vkbootstrap/"

DescriptorLayoutBuilder :: struct {
	bindings: [dynamic]vk.DescriptorSetLayoutBinding,
}

descriptor_builder_add_binding :: proc(
	self: ^DescriptorLayoutBuilder,
	binding: u32,
	type: vk.DescriptorType,
) {
	newbind := vk.DescriptorSetLayoutBinding{}
	newbind.binding = binding
	newbind.descriptorCount = 1
	newbind.descriptorType = type

	append(&self.bindings, newbind)
}

descriptor_builder_clear :: proc(self: ^DescriptorLayoutBuilder) {
	clear(&self.bindings)
}

descriptor_builder_build :: proc(
	self: ^DescriptorLayoutBuilder,
	device: vk.Device,
	shaderStages: vk.ShaderStageFlags,
	pNext: rawptr = nil,
	flags: vk.DescriptorSetLayoutCreateFlags = {},
) -> (
	set: vk.DescriptorSetLayout,
	err: vkb.Error,
) {
	for &b in self.bindings {
		b.stageFlags |= shaderStages
	}

	info := vk.DescriptorSetLayoutCreateInfo {
		sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
	}
	info.pNext = pNext

	info.pBindings = raw_data(self.bindings)
	info.bindingCount = cast(u32)len(self.bindings)

	info.flags = flags

	vkb.vk_check(vk.CreateDescriptorSetLayout(device, &info, nil, &set)) or_return

	return set, err
}

PoolSizeRatio :: struct {
	type:  vk.DescriptorType,
	ratio: f32,
}

DescriptorAllocator :: struct {
	pool: vk.DescriptorPool,
}

descriptor_allocator_init_pool :: proc(
	self: ^DescriptorAllocator,
	device: vk.Device,
	maxSets: u32,
	poolRatios: []PoolSizeRatio,
) {
	pool_sizes: [dynamic]vk.DescriptorPoolSize
	defer delete(pool_sizes)
	for ratio in poolRatios {
		append(
			&pool_sizes,
			vk.DescriptorPoolSize {
				type = ratio.type,
				descriptorCount = cast(u32)(ratio.ratio * cast(f32)maxSets),
			},
		)
	}

	pool_info := vk.DescriptorPoolCreateInfo {
		sType = .DESCRIPTOR_POOL_CREATE_INFO,
		pNext = nil,
	}

	pool_info.flags = {}
	pool_info.maxSets = maxSets
	pool_info.poolSizeCount = cast(u32)len(pool_sizes)
	pool_info.pPoolSizes = raw_data(pool_sizes)

	vk.CreateDescriptorPool(device, &pool_info, nil, &self.pool)
}
descriptor_allocator_clear_descriptors :: proc(self: ^DescriptorAllocator, device: vk.Device) {
	vk_assert(vk.ResetDescriptorPool(device, self.pool, {}))
}
descriptor_allocator_destroy_pool :: proc(self: ^DescriptorAllocator, device: vk.Device) {
	vk.DestroyDescriptorPool(device, self.pool, nil)
}

descriptor_allocator_allocate :: proc(
	self: ^DescriptorAllocator,
	device: vk.Device,
	layout: vk.DescriptorSetLayout,
) -> vk.DescriptorSet {
	alloc_info := vk.DescriptorSetAllocateInfo {
		sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
		pNext = nil,
	}

	alloc_info.descriptorPool = self.pool
	alloc_info.descriptorSetCount = 1
	local_layout := layout
	alloc_info.pSetLayouts = &local_layout

	ds: vk.DescriptorSet
	vk.AllocateDescriptorSets(device, &alloc_info, &ds)

	return ds
}
