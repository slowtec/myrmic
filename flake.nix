{
  description = "myrmic development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          devShells.default = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [
              # rustup rather than a Nix-built toolchain: `myrmic build` runs
              # `cargo +<toolchain>`, and the rust-toolchain.toml files pick
              # stable or nightly per directory.
              rustup
              cmake # a C dependency of the CLI
              pkg-config
              git
              llvmPackages.clang-unwrapped # clang without nix wrapper, cross-compiles WAMR for bare-metal RISC-V

              # These are not actual dependencies
              # but tools that can help with development.
              cargo-nextest
              cargo-deny
              espflash
            ];

            # D-Bus, for the CLI's `ble` feature.
            buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.dbus ];

            LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
          };
        }
      );
}
