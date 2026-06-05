{
  description = "Vulkan guide written in Odin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixgl.url = "github:nix-community/nixGL";
    nixgl.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixgl }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      nixGL = nixgl.packages.${system};

      runtimeLibs = with pkgs; [
        vulkan-loader
        SDL2
        sdl3
        stdenv.cc.cc.lib
        libcxx
        libGL
      ];
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          odin
          ols
          vulkan-tools
          vulkan-validation-layers
          glslang
          premake5
          bash
          # Add the right nixVulkan wrapper for your GPU
          nixGL.nixVulkanIntel   # Intel / Mesa (most common)
          # nixGL.nixVulkanMesa  # alternative broad Mesa
          # nixGL.auto.nixVulkanNvidia or nixGL.nixVulkanNvidia if you have NVIDIA
        ];

        buildInputs = runtimeLibs ++ (with pkgs; [
          vulkan-headers
          SDL2.dev
          sdl3.dev
          xorg.libX11
          xorg.libXrandr
          xorg.libXinerama
          xorg.libXcursor
          xorg.libXi
          wayland
          libxkbcommon
        ]);

        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath runtimeLibs;

        VK_LAYER_PATH = "${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d";

        # Optional: force X11 if you have Wayland issues
        # SDL_VIDEODRIVER = "x11";
      };
    };
}
