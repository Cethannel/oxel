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
        SDL2
        stdenv.cc.cc.lib
        libcxx
				libllvm
      ];

			nativeBuildInputs = with pkgs; [
				odin
			];

			devShellBase = {
				packages = with pkgs; [
						ols
						vulkan-tools
						vulkan-validation-layers
						bash
						mangohud
				] ++ nativeBuildInputs;

        buildInputs = runtimeLibs ++ (with pkgs; [
          SDL2.dev
        ]);

        LD_LIBRARY_PATH = "/usr/lib64:${pkgs.lib.makeLibraryPath runtimeLibs}";

        VK_LAYER_PATH = "${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d";
			};

			vmaSrc = pkgs.fetchFromGitHub {
        owner = "GPUOpen-LibrariesAndSDKs";
        repo = "VulkanMemoryAllocator";
        rev = "v3.3.0";
        sha256 = "sha256-TPEqV8uHbnyphLG0A+b2tgLDQ6K7a2dOuDHlaFPzTeE=";
      };

			vulkanHeadersSrc = pkgs.fetchFromGitHub {
        owner = "KhronosGroup";
        repo = "Vulkan-Headers";
        rev = "v1.4.337";
        sha256 = "sha256-+adxYPqiOQelDru1R+8feOq3G+VKf5PqtffQYEGmfjQ=";
      };

			vma = pkgs.stdenv.mkDerivation {
				pname = "vma";
        version = "3.3.0";

        src = ./vma;

        dontConfigure = true;

				buildInputs = with pkgs; [
					vulkan-loader
					vulkan-headers
				];

				nativeBuildInputs = with pkgs; [
					premake5
					git
				];

				postUnpack = ''
					mkdir -p $sourceRoot/build/deps/vma
					cp -r ${vmaSrc}/* $sourceRoot/build/deps/vma
					chmod -R u+w $sourceRoot/build/deps/vma

					mkdir -p $sourceRoot/build/deps/vulkan_headers
					cp -r ${vulkanHeadersSrc}/* $sourceRoot/build/deps/vulkan_headers
					chmod -R u+w $sourceRoot/build/deps/vulkan_headers
				'';

        buildPhase = ''
					premake5 --vk-version=3 gmake
					pushd build/make/linux
					make -j 32
					popd
        '';

        installPhase = ''
          mkdir -p $out/lib
          cp libvma_linux_x86_64.a $out/lib
          # If you actually build a static lib with just build_vma, put it here
        '';
			};

			imgui = pkgs.stdenv.mkDerivation {
        pname = "imgui";
        version = "unstable";

        src = ./.;

        nativeBuildInputs = with pkgs; [
					just
					python3
					python3Packages.ply
					clang
				];

				buildInputs = with pkgs; [
					vulkan-headers
				];

        buildPhase = ''
          just build_imgui
        '';

        installPhase = ''
          mkdir -p $out/lib
          cp -r vendor/gitlab.com/L-4/odin-imgui/imgui_linux_x64.a $out/lib/ 2>/dev/null || true
          # adjust path as needed
        '';
      };

			shaders = pkgs.stdenv.mkDerivation {
        pname = "oxel-shaders";
        version = "0.1";

        src = ./.;

        nativeBuildInputs = with pkgs; [ just glslang parallel ];

        buildPhase = ''
          just shaders
        '';

        installPhase = ''
          mkdir -p $out/share/shaders
          cp -r shaders/* $out/share/shaders/ 2>/dev/null || true
        '';
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

					buildPhase = ''
						set -euo pipefail

            echo "=== Using cached VMA ==="
						# Copy from cached derivation if needed
						mkdir -p vma/build/deps/vma
						ls ${vma}/lib/*
						cp -r ${vma}/lib/* vma || true

						echo "=== Using cached imgui ==="
						# Link or copy cached imgui
						cp -r ${imgui}/lib/* vendor/gitlab.com/L-4/odin-imgui/

						echo "=== Using cached shaders ==="
						mkdir -p shaders
						cp -r ${shaders}/share/shaders/* shaders/ || true

						echo "=== Building Odin ==="
						odin build . -out:oxel \
							-extra-linker-flags="-fuse-ld=${lldWrapper}/bin/ld.lld -v"
					'';

					installPhase = ''
						mkdir -p $out/bin

						cp oxel $out/bin/oxel
					'';

					postFixup = ''
						wrapProgram $out/bin/oxel \
              --set LD_LIBRARY_PATH "/usr/lib64:${pkgs.lib.makeLibraryPath runtimeLibs}" \
              --set VK_LAYER_PATH "${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d"
					'';
				};
				default = self.packages.${system}.oxel;
			};

      devShells.${system} = {
				default = pkgs.mkShell devShellBase;
				nu = pkgs.mkShell (devShellBase // {
          name = "oxel-nu-devshell";

          packages = devShellBase.packages ++ (with pkgs; [
            nushell
          ]);

          shellHook = ''
            echo "========================================"
            echo "🚀 Oxel Nushell Development Environment"
            echo "========================================"
            echo "Nushell version: $(nu --version)"
            echo ""

            # Force exec nushell
            exec ${pkgs.nushell}/bin/nu
          '';
        });
			};
    };
}
