{
  description = "Odin project with Vulkan, Wayland, X11, SDL2, ImGui (dynamic preferred)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        runtimeLibs = with pkgs; [
          vulkan-loader
          SDL2
          wayland
          libxkbcommon
          libX11
          libXcursor
          libXi
          libXrandr
          libXinerama
          # Add if your project actually needs the C++ ImGui lib (rare for Odin bindings)
          # imgui  # ← usually NOT needed — Odin vendor bindings use their own .a or .so
        ];

        buildLibs = runtimeLibs ++ (with pkgs; [
          vulkan-headers
          wayland-protocols
          pkg-config
          # Explicitly bring in C++ runtime (fixes -lc++)
          stdenv.cc.cc.lib    # libstdc++.so
          # or for clang/libc++: llvmPackages.libcxx
        ]);

      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "odin-vulkan-project";
          version = "0.1.0";

          src = ./.;

          nativeBuildInputs = with pkgs; [ odin makeWrapper pkg-config ];
          buildInputs = buildLibs;

          # If you must use static vendor libs, see workaround below
          buildPhase = ''
            echo "Building Odin project..."
            odin build . -out:odin-project -o:speed
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp odin-project $out/bin/
          '';

          postFixup = ''
            wrapProgram $out/bin/odin-project \
              --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath runtimeLibs}"
          '';

          meta.platforms = [ "x86_64-linux" "aarch64-linux" ];
        };

        apps.default = {
          type = "app";
          program = "$$   {self.packages.   $${system}.default}/bin/odin-project";
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ self.packages.${system}.default ];
          packages = with pkgs; [ odin ];

          shellHook = ''
            echo "Odin dev shell (Vulkan + Wayland + X11 + SDL2)"
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath runtimeLibs}:$LD_LIBRARY_PATH"
          '';
        };
      }
    );
}
