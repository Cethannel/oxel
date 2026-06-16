{
  description = "Vulkan guide written in Odin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      runtimeLibs = with pkgs; [
        vulkan-loader
        SDL2
        sdl3
        stdenv.cc.cc.lib
        libcxx
        libGL
        imgui
				libllvm
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
          mangohud
        ];

        buildInputs = runtimeLibs ++ (with pkgs; [
          vulkan-headers
          SDL2.dev
          sdl3.dev
          libX11
          libXrandr
          libXinerama
          libXcursor
          libXi
          wayland
          libxkbcommon
        ]);

        LD_LIBRARY_PATH = "/usr/lib64:${pkgs.lib.makeLibraryPath runtimeLibs}";

        VK_LAYER_PATH = "${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d";
      };
    };
}
