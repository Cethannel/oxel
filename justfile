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

[working-directory('vma')]
build_vma:
    pwd
    nix develop --command bash -c 'premake5 --vk-version=3 gmake'
    cd build/make/linux && make

nix_run: build
    LD_LIBRARY_PATH="/usr/lib64:$LD_LIBRARY_PATH" __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only ./oxel

nix_mango: build
    LD_LIBRARY_PATH="/usr/lib64:$LD_LIBRARY_PATH" __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only mangohud ./oxel

nix_gdb_run: build
    LD_LIBRARY_PATH="/usr/lib64:$LD_LIBRARY_PATH" __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only gdb --args ./oxel

gdb_alloc: build
    LD_LIBRARY_PATH="/usr/lib64:$LD_LIBRARY_PATH" __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only gdb -ex "source ignore_log_bp.py" -ex 'python IgnoreLogBreakpoint("your_function_name")' --args ./oxel
