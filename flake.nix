{
  description = "A Nix-flake-based Odin development environment";

  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";

  outputs =
    { self, ... }@inputs:

    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forEachSupportedSystem =
        f:
        inputs.nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            pkgs = import inputs.nixpkgs { inherit system; };
          }
        );
    in
    {
      devShells = forEachSupportedSystem (
        { pkgs }:
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              odin
              clang
              llvmPackages.libcxx
              SDL2
              vulkan-headers
              vulkan-tools          # for testing `vulkaninfo` inside the shell
            ];

            shellHook = ''
              # Nix libc++ for link-time (-lc++) and runtime
              export LIBRARY_PATH="${pkgs.lib.makeLibraryPath [
                pkgs.llvmPackages.libcxx
              ]}:$LIBRARY_PATH"
              export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [
                pkgs.SDL2
                pkgs.llvmPackages.libcxx
              ]}:/usr/lib64:$LD_LIBRARY_PATH"

              # Add Gentoo's slotted LLVM (fixes the exact libLLVM.so.21.1 error)
              for llvm_lib in /usr/lib64/llvm/*/lib; do
                if [ -d "$llvm_lib" ]; then
                  export LD_LIBRARY_PATH="$llvm_lib:$LD_LIBRARY_PATH"
                  echo "Added Gentoo LLVM path: $llvm_lib"
                  break
                fi
              done

              # Use Gentoo's native Vulkan loader + layers
              export VK_LAYER_PATH="/usr/share/vulkan/explicit_layer.d"

              # Point to Gentoo's ICD files (RADV driver)
              ICD_PATHS=$(find /etc/vulkan/icd.d /usr/share/vulkan/icd.d -name "*.json" 2>/dev/null | tr '\n' ':' | sed 's/:$//')
              if [ -n "$ICD_PATHS" ]; then
                export VK_DRIVER_FILES="$ICD_PATHS"
                export VK_ICD_FILENAMES="$ICD_PATHS"
              fi

              echo "Using Gentoo system Vulkan + SDL2"
            '';
          };
        }
      );
    };
}
