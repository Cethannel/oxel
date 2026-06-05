package engine

import "core:log"
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
	defer delete(self.bindings)
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

DescriptorAllocatorGrowable :: struct {
	ratios:      [dynamic]PoolSizeRatio,
	fullPools:   [dynamic]vk.DescriptorPool,
	readyPools:  [dynamic]vk.DescriptorPool,
	setsPerPool: u32,
}

descriptor_allocator_growable_init :: proc(
	self: ^DescriptorAllocatorGrowable,
	device: vk.Device,
	maxSets: u32,
	poolRatios: []PoolSizeRatio,
) {
	clear(&self.ratios)

	for r in poolRatios {
		append(&self.ratios, r)
	}

	newPool := descriptor_allocator_growable_create_pool(self, device, maxSets, poolRatios)

	self.setsPerPool = cast(u32)(cast(f64)maxSets * 1.5) //grow it next allocation

	append(&self.readyPools, newPool)
}

descriptor_allocator_growable_deinit :: proc(self: ^DescriptorAllocatorGrowable) {
	delete(self.ratios)
	delete(self.fullPools)
	delete(self.readyPools)
}

descriptor_allocator_growable_clear_pools :: proc(
	self: ^DescriptorAllocatorGrowable,
	device: vk.Device,
) -> vk.Result {
	for p in self.readyPools {
		vk.ResetDescriptorPool(device, p, {}) or_return
	}
	for p in self.fullPools {
		vk.ResetDescriptorPool(device, p, {}) or_return
		append(&self.readyPools, p)
	}
	clear(&self.fullPools)

	return .SUCCESS
}

descriptor_allocator_growable_destroy_pools :: proc(
	self: ^DescriptorAllocatorGrowable,
	device: vk.Device,
) {
	for p in self.readyPools {
		vk.DestroyDescriptorPool(device, p, nil)
	}
	clear(&self.readyPools)
	for p in self.fullPools {
		vk.DestroyDescriptorPool(device, p, nil)
	}
	clear(&self.fullPools)
}

descriptor_allocator_growable_allocate :: proc(
	dag: ^DescriptorAllocatorGrowable,
	device: vk.Device,
	layout: vk.DescriptorSetLayout,
	pNext: rawptr = nil,
) -> vk.DescriptorSet {
	poolToUse := descriptor_allocator_growable_get_pool(dag, device)

	allocInfo: vk.DescriptorSetAllocateInfo = {}
	allocInfo.pNext = pNext
	allocInfo.sType = .DESCRIPTOR_SET_ALLOCATE_INFO
	allocInfo.descriptorPool = poolToUse
	allocInfo.descriptorSetCount = 1
	lLayout := layout
	allocInfo.pSetLayouts = &lLayout

	ds: vk.DescriptorSet
	result := vk.AllocateDescriptorSets(device, &allocInfo, &ds)

	//allocation failed. Try again
	if (result == .ERROR_OUT_OF_POOL_MEMORY || result == .ERROR_FRAGMENTED_POOL) {
		log.warn("Allocation failed, trying again")

		append(&dag.fullPools, poolToUse)

		poolToUse = descriptor_allocator_growable_get_pool(dag, device)
		allocInfo.descriptorPool = poolToUse

		assert(vk.AllocateDescriptorSets(device, &allocInfo, &ds) == .SUCCESS)
	}

	append(&dag.readyPools, poolToUse)
	return ds
}

@(private)
descriptor_allocator_growable_get_pool :: proc(
	self: ^DescriptorAllocatorGrowable,
	device: vk.Device,
) -> vk.DescriptorPool {
	newPool: vk.DescriptorPool
	if (len(self.readyPools) != 0) {
		newPool = pop(&self.readyPools)
	} else {
		//need to create a new pool
		newPool = descriptor_allocator_growable_create_pool(
			self,
			device,
			self.setsPerPool,
			self.ratios[:],
		)

		self.setsPerPool = cast(u32)(cast(f32)self.setsPerPool * 1.5)
		if (self.setsPerPool > 4092) {
			self.setsPerPool = 4092
		}
	}

	return newPool
}

@(private)
descriptor_allocator_growable_create_pool :: proc(
	self: ^DescriptorAllocatorGrowable,
	device: vk.Device,
	setCount: u32,
	poolRatios: []PoolSizeRatio,
) -> vk.DescriptorPool {
	poolSizes: [dynamic]vk.DescriptorPoolSize
	defer delete(poolSizes)
	for ratio in poolRatios {
		append(
			&poolSizes,
			vk.DescriptorPoolSize {
				type = ratio.type,
				descriptorCount = cast(u32)(ratio.ratio * cast(f32)setCount),
			},
		)
	}

	pool_info: vk.DescriptorPoolCreateInfo = {}
	pool_info.sType = .DESCRIPTOR_POOL_CREATE_INFO
	pool_info.flags = {}
	pool_info.maxSets = setCount
	pool_info.poolSizeCount = cast(u32)len(poolSizes)
	pool_info.pPoolSizes = raw_data(poolSizes)

	newPool: vk.DescriptorPool
	vk.CreateDescriptorPool(device, &pool_info, nil, &newPool)
	return newPool
}

DescriptorWriter :: struct {
	imageInfos:  [dynamic]vk.DescriptorImageInfo, // std::deque
	bufferInfos: [dynamic]vk.DescriptorBufferInfo, // std::deque
	writes:      [dynamic]vk.WriteDescriptorSet,
}

descriptor_writer_write_image :: proc(
	dw: ^DescriptorWriter,
	binding: u32,
	image: vk.ImageView,
	sampler: vk.Sampler,
	layout: vk.ImageLayout,
	type: vk.DescriptorType,
) {
	i, _ := append(
		&dw.imageInfos,
		vk.DescriptorImageInfo{sampler = sampler, imageView = image, imageLayout = layout},
	)
	info := &dw.imageInfos[i - 1]

	write: vk.WriteDescriptorSet = {
		sType = .WRITE_DESCRIPTOR_SET,
	}

	write.dstBinding = binding
	write.dstSet = 0 //left empty for now until we need to write it
	write.descriptorCount = 1
	write.descriptorType = type
	write.pImageInfo = info

	append(&dw.writes, write)
}

descriptor_writer_write_buffer :: proc(
	dw: ^DescriptorWriter,
	binding: u32,
	buffer: vk.Buffer,
	size: vk.DeviceSize,
	offset: vk.DeviceSize,
	type: vk.DescriptorType,
) {
	i, _ := append(
		&dw.bufferInfos,
		vk.DescriptorBufferInfo{buffer = buffer, offset = offset, range = size},
	)
	info := &dw.bufferInfos[i - 1]

	write: vk.WriteDescriptorSet = {
		sType = .WRITE_DESCRIPTOR_SET,
	}

	write.dstBinding = binding
	write.dstSet = 0 //left empty for now until we need to write it
	write.descriptorCount = 1
	write.descriptorType = type
	write.pBufferInfo = info

	append(&dw.writes, write)
}

descriptor_writer_clear :: proc(dw: ^DescriptorWriter) {
	delete(dw.imageInfos)
	delete(dw.writes)
	delete(dw.bufferInfos)
}
descriptor_writer_update_set :: proc(
	dw: ^DescriptorWriter,
	device: vk.Device,
	set: vk.DescriptorSet,
) {

	for &write in dw.writes {
		write.dstSet = set
	}

	vk.UpdateDescriptorSets(device, cast(u32)len(dw.writes), raw_data(dw.writes), 0, nil)

	descriptor_writer_clear(dw)
}
