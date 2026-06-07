build:
	odin build . -debug

run: build
	LD_LIBRARY_PATH="/lib64:${LD_LIBRARY_PATH:-}" ./oxel

patch_run: build
	patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 ./oxel
	./oxel

shaders:
	cd shaders && ./compile.sh

[working-directory: 'vma']
build_vma:
	pwd
	nix develop --command bash -c 'premake5 --vk-version=3 gmake'
	cd build/make/linux && make

nix_run: build
	nixVulkanIntel ./oxel
