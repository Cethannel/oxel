{ pkgs, lib, config, inputs, ... }:
let
  runtimeLibs = with pkgs; [
    SDL2
    vulkan-loader
    stdenv.cc.cc.lib
    libcxx
    libllvm
    # add more if needed later (libdrm, wayland, libxkbcommon, …)
  ];
in
{
  env = {
    VK_LAYER_PATH = "${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d";
  };

  packages = with pkgs; [
    git
    ols
    vulkan-tools
    vulkan-validation-layers
    shader-slang          # or whatever you use
    # optional but useful
    # mangohud
  ] ++ runtimeLibs;

  languages.odin.enable = true;

  # This is the important part – mirror the working shellHook
  enterShell = ''
    SYS_LLVM_LIB=$(ls -d /usr/lib/llvm/*/lib64 2>/dev/null | sort -V | tail -1)
    export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath runtimeLibs}:/usr/lib64''${SYS_LLVM_LIB:+:$SYS_LLVM_LIB}"
    echo "LD_LIBRARY_PATH set for host Vulkan ICDs + Nix libs"
  '';

  # Optional: keep the test you already had
  enterTest = ''
    echo "Running tests"
    git --version | grep --color=auto "${pkgs.git.version}"
  '';
}
