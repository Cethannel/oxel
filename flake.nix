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
        vulkan-headers
        SDL2
        sdl3
        stdenv.cc.cc.lib
        libcxx
        libGL
				libllvm
        imgui
      ];

			nativeBuildInputs = with pkgs; [
          odin
          glslang
          premake5
					just
					git
					bash
					parallel
					python3
					python3Packages.ply
					clang
					lldWrapper
					ripgrep
					eza
			];

			vmaSrc = pkgs.fetchFromGitHub {
        owner = "GPUOpen-LibrariesAndSDKs";
        repo = "VulkanMemoryAllocator";
        rev = "v3.3.0";                    # Update this if you want a newer tag
        sha256 = "sha256-TPEqV8uHbnyphLG0A+b2tgLDQ6K7a2dOuDHlaFPzTeE="; # ← Nix will tell you the real hash
      };

			vulkanHeadersSrc = pkgs.fetchFromGitHub {
        owner = "KhronosGroup";
        repo = "Vulkan-Headers";
        rev = "v1.4.337";                    # Update this if you want a newer tag
        sha256 = "sha256-+adxYPqiOQelDru1R+8feOq3G+VKf5PqtffQYEGmfjQ="; # ← Nix will tell you the real hash
      };

      # Odin emits -l:/abs/path.a for foreign imports, but linkers treat -l: as a
      # filename search in -L dirs (not a direct path), so they fail in the nix
      # sandbox where -L/ isn't automatically added. This wrapper converts those
      # absolute-path -l: flags to positional args, which always work.
      lldWrapper = pkgs.writeShellScriptBin "ld.lld" ''
        args=()
        for arg in "$@"; do
          if [[ "$arg" == -l:/* ]]; then
            args+=("''${arg#-l:}")
          else
            args+=("$arg")
          fi
        done
        exec ${pkgs.lld}/bin/ld.lld "''${args[@]}"
      '';
    in
    {
			packages.${system} = {
				oxel = pkgs.stdenv.mkDerivation {
					pname = "oxel";
					version = "0.1.0";

					src = ./.;

					nativeBuildInputs = with pkgs; [
						makeWrapper
					] ++ nativeBuildInputs;

					buildInputs = runtimeLibs;

					dontConfigure = true;

					dontStrip = true;

					postUnpack = ''
						mkdir -p $sourceRoot/vma/build/deps/vma
            cp -r ${vmaSrc}/* $sourceRoot/vma/build/deps/vma
            chmod -R u+w $sourceRoot/vma/build/deps/vma
						mkdir -p $sourceRoot/vma/build/deps/vulkan_headers
            cp -r ${vulkanHeadersSrc}/* $sourceRoot/vma/build/deps/vulkan_headers
            chmod -R u+w $sourceRoot/vma/build/deps/vulkan_headers
          '';

					buildPhase = ''
						set -euo pipefail

            echo "=== Building VMA ==="
            just build_vma

            echo "=== Building imgui ==="
            just build_imgui

						ls -lah vma/ vendor/gitlab.com/L-4/odin-imgui/   # debug

						rg imgui_linux_x64.a

  echo "=== Compiling shaders ==="
  just shaders

  echo "=== Building Odin ==="
  odin build . -out:oxel \
    -extra-linker-flags="-fuse-ld=${lldWrapper}/bin/ld.lld -v"
					'';

					installPhase = ''
						mkdir -p $out/bin
						cp oxel $out/bin/oxel
						wrapProgram $out/bin/oxel \
							--set LD_LIBRARY_PATH ${pkgs.lib.makeLibraryPath runtimeLibs} \
							--set VK_LAYER_PATH ${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d
					'';
				};
				default = self.packages.${system}.oxel;
			};

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          ols
          vulkan-tools
          vulkan-validation-layers
          bash
          mangohud
        ] ++ nativeBuildInputs;

        buildInputs = runtimeLibs ++ (with pkgs; [
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
