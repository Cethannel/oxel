{
  description = "Odin Vulkan project with manual linking to fix vendored static .a paths";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nixgl.url = "github:nix-community/nixGL";
  };

  outputs = { self, nixpkgs, flake-utils, nixgl }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        runtimeLibs = with pkgs; [
          vulkan-loader
          vulkan-validation-layers
          SDL2
          wayland
          libxkbcommon
          libX11
          libXcursor
          libXi
          libXrandr
          libXinerama
          freetype
          harfbuzz
          libcxx
        ];

        pythonWithPly = pkgs.python3.withPackages (ps: [ ps.ply ]);

        cppStdlib = pkgs.stdenv.cc.cc.lib;

        # Path to Odin's own vendored cgltf static lib (the one that was also failing)
        cgltfA = "${pkgs.odin}/share/vendor/cgltf/lib/cgltf.a";

      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "odin-vulkan-project";
          version = "0.1.0";

          src = ./.;

          nativeBuildInputs = with pkgs; [ odin clang makeWrapper pkg-config pythonWithPly ];
          buildInputs = runtimeLibs ++ ( with pkgs; [ cppStdlib vulkan-headers wayland-protocols ]);

                    buildPhase = ''
            echo "=== Building vendored static libs ==="

            pushd vendor/gitlab.com/L-4/odin-imgui
            python build.py linux
            popd

            pushd vma
            odin build . -build-mode:lib -o:speed -out:libvma_linux_x86_64.a
            popd

            ls -lah vendor/gitlab.com/L-4/odin-imgui/imgui_linux_x64.a
            ls -lah vma/libvma_linux_x86_64.a

            echo "=== Compiling Odin to single object ==="
            odin build . -build-mode:obj -o:speed -out:project.o

            echo "=== Manual linking — static libs LAST + -lm ==="
            clang project.o \
              -o odin-project \
              -L${pkgs.lib.makeLibraryPath runtimeLibs} \
              -L${pkgs.lib.makeLibraryPath [cppStdlib]} \
              -lvulkan \
              -lSDL2 \
              -lwayland-client -lwayland-egl \
              -lxkbcommon \
              -lX11 -lXcursor -lXi -lXrandr -lXinerama \
              -lfreetype -lharfbuzz \
              -lstdc++ \
              -lm \                        # ← added for floorf, sinf, etc.
              vendor/gitlab.com/L-4/odin-imgui/imgui_linux_x64.a \
              vma/libvma_linux_x86_64.a \
              ${cgltfA}
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp odin-project $out/bin/
          '';

          postFixup = ''
            wrapProgram $out/bin/odin-project \
              --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath runtimeLibs}"
          '';

          meta.platforms = pkgs.lib.platforms.linux;
        };

        apps.default = flake-utils.lib.mkApp {
          drv = self.packages.${system}.default;
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ odin clang ] ++ runtimeLibs ++ [ cppStdlib ] ++ [nixgl.packages.${system}.nixVulkanIntel];

          shellHook = ''
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath (runtimeLibs ++ [cppStdlib])}:$LD_LIBRARY_PATH"
            echo "Odin dev shell ready - use 'odin build . -o:speed' for fast iteration (runtime libs are on PATH)"
          '';
        };
      }
    );
}
