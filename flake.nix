{
  description = "Vulkan guide written in Odin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      runtimeLibs = with pkgs; [
        vulkan-loader
        SDL2
        stdenv.cc.cc.lib
				libcxx
      ];
    in
    {
      packages.${system}.default = pkgs.stdenv.mkDerivation {
        pname = "vulkan-guide";
        version = "0.1.0";
        src = ./.;

        nativeBuildInputs = with pkgs; [
          odin
          autoPatchelfHook
	  premake5
        ];

        buildInputs = runtimeLibs ++ (with pkgs; [
          vulkan-headers
          vulkan-validation-layers
        ]);

        buildPhase = ''
          odin build . -out:vulkan_guide
        '';

        installPhase = ''
          mkdir -p $out/bin $out/share/vulkan-guide/shaders
          cp vulkan_guide $out/bin/
          cp shaders/*.spv $out/share/vulkan-guide/shaders/
        '';
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          odin
          ols
          vulkan-tools
          vulkan-validation-layers
          glslang
	  premake5
        ];

        buildInputs = runtimeLibs ++ (with pkgs; [
          vulkan-headers
          SDL2.dev
        ]);

        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath runtimeLibs;

        VK_LAYER_PATH = "${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d";
      };
    };
}
