build:
	odin build . -debug

patch: build
	patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 ./vulkan_guide

run: patch
	./vulkan_guide

shaders:
	cd shaders && ./compile.sh
