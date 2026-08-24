build:
    odin build . -debug
    cd base_mod && odin build . -debug -build-mode:dynamic

run: build
    ./oxel

shaders:
    cd shaders && bash ./compile.sh

build_vma:
    cd vma && premake5 --vk-version=3 gmake
    cd vma/build/make/linux && make

build_imgui:
    cd vendor/gitlab.com/L-4/odin-imgui && python3 build.py

nix_gdb_run: build
    __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only gdb --args ./oxel

gdb_alloc: build
    __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only gdb -ex "source ignore_log_bp.py" -ex 'python IgnoreLogBreakpoint("your_function_name")' --args ./oxel

debug:
    odin build .
    raddbg
