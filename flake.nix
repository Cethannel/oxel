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
        # Apply nixGL overlay correctly (single function, not .overlays attrset)
        pkgs = import nixpkgs {
          inherit system;
          #overlays = [ nixgl.overlay ];  # ← this is usually the right one
          # If the above fails with "attribute 'overlay' missing", try:
          # overlays = [ nixgl.overlays.default ];
        };

        runtimeLibs = with pkgs; [
          vulkan-loader
          vulkan-validation-layers  # good for dev/debug
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
          libcxx  # if you need libc++ explicitly
        ];

        cppStdlib = pkgs.stdenv.cc.cc.lib;  # for -lstdc++

      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "odin-vulkan-project";
          version = "0.1.0";

          src = ./.;

          nativeBuildInputs = with pkgs; [ odin clang makeWrapper pkg-config ];
          buildInputs = runtimeLibs ++ (with pkgs; [
            cppStdlib
            vulkan-headers
            wayland-protocols
						tree
						python3
						git
            # nixgl stuff if you want to wrap the binary with it later
          ]);

          buildPhase = ''
            echo "Compiling Odin sources to objects..."
            # If your project is a package (multiple files), this works.
            # If single-file (e.g. main.odin), add -file:
            # odin build main.odin -file -o:speed -build-mode:obj -out:odin.obj
						# ---- imgui ----
						pushd vendor/gitlab.com/L-4/odin-imgui
						# assuming it has a build.py or similar; adjust to whatever builds imgui_linux_x64.a
						python build.py linux    # ← or whatever command creates the .a
						# or if it uses a Makefile / odin build ... -build-mode:lib etc.
						popd

						# ---- VMA ----
						pushd vendor/vma
						# VMA is header-only in many cases, but if you have a .odin + .a build step:
						# odin build . -build-mode:lib -o:speed -out:libvma_linux_x86_64.a   # adjust
						# or use premade build script if present
						popd

						tree .
						pwd
            odin build . -o:speed
						echo "Built"
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
            echo "Odin dev shell with manual link setup"
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath (runtimeLibs ++ [cppStdlib])}:$LD_LIBRARY_PATH"
          '';
        };

        # Optional: if you want to run with nixGL wrapper (e.g. nixGLIntel or auto-default)
        # packages.nixgl-wrapped = pkgs.nixgl.auto.nixGLDefault self.packages.${system}.default;
        # apps.nixgl-run = flake-utils.lib.mkApp { drv = self.packages.${system}.nixgl-wrapped; };
      }
    );
}
