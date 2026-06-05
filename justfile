build:
	odin build . -debug

patch: build
	patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 ./oxel

run: patch
	./oxel

shaders:
	cd shaders && ./compile.sh

[working-directory: 'vma']
build_vma:
	pwd
	nix develop --command bash -c 'premake5 --vk-version=3 gmake'
	cd build/make/linux && make
