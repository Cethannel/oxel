build:
    odin build . -debug

run: build
    ./oxel

shaders:
    cd shaders && ./compile.sh

[working-directory('vma')]
build_vma:
    nix develop --command bash -c 'premake5 --vk-version=3 gmake'
    cd build/make/linux && make

nix_gdb_run: build
    __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only gdb --args ./oxel

gdb_alloc: build
    __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only gdb -ex "source ignore_log_bp.py" -ex 'python IgnoreLogBreakpoint("your_function_name")' --args ./oxel
