build:
	odin build . -debug

run: build
	LD_LIBRARY_PATH="/lib64:${LD_LIBRARY_PATH:-}" ./oxel

patch: build
	patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 ./oxel

patch_run: patch
	./oxel

patch_mango: patch
	MANGOHUD_CONFIG=full,position=top-left mangohud ./oxel

shaders:
	cd shaders && ./compile.sh

[working-directory: 'vma']
build_vma:
	pwd
	nix develop --command bash -c 'premake5 --vk-version=3 gmake'
	cd build/make/linux && make

nix_run: build
	nixVulkanIntel ./oxel

nix_gdb_run: build
	nixVulkanIntel gdb --args ./oxel

gdb_alloc: build
	nixVulkanIntel gdb -ex "source ignore_log_bp.py" -ex 'python IgnoreLogBreakpoint("your_function_name")' --args ./oxel
