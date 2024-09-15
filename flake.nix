{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    rust-overlay.url = "github:oxalica/rust-overlay";
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      treefmt-nix,
      rust-overlay,
      crane,
    }:
    flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
      ]
      (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import rust-overlay) ];
          };
          lib = pkgs.lib;
          rust = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
          treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
          craneLib = (crane.mkLib pkgs).overrideToolchain rust;
          dependencies = with pkgs; [
            pkg-config
            udev
            alsa-lib
            vulkan-loader
            xorg.libX11
            xorg.libXcursor
            xorg.libXi
            xorg.libXrandr
            libxkbcommon
            wayland
          ];
          src = ./.;
          cargoArtifacts = craneLib.buildDepsOnly {
            inherit src;
            buildInputs = dependencies;
          };
          bevy-clicker = craneLib.buildPackage {
            inherit src cargoArtifacts;
            buildInputs = dependencies;
            strictDeps = true;

            doCheck = true;
          };
          cargo-clippy = craneLib.cargoClippy {
            inherit src cargoArtifacts;
            buildInputs = dependencies;
            cargoClippyExtraArgs = "--verbose -- --deny warnings";
          };
          cargo-doc = craneLib.cargoDoc {
            inherit src cargoArtifacts;
            buildInputs = dependencies;
          };
          llvm-cov-text = craneLib.cargoLlvmCov {
            inherit cargoArtifacts src;
            buildInputs = dependencies;
            cargoExtraArgs = "--locked";
            cargoLlvmCovCommand = "test";
            cargoLlvmCovExtraArgs = "--text --output-dir $out";
          };
          llvm-cov = craneLib.cargoLlvmCov {
            inherit cargoArtifacts src;
            buildInputs = dependencies;
            cargoExtraArgs = "--locked";
            cargoLlvmCovCommand = "test";
            cargoLlvmCovExtraArgs = "--html --output-dir $out";
          };
        in
        {
          formatter = treefmtEval.config.build.wrapper;

          packages = {
            inherit bevy-clicker llvm-cov llvm-cov-text;
            default = bevy-clicker;
            doc = cargo-doc;
          };

          apps.default = flake-utils.lib.mkApp {
            drv = self.packages.${system}.default;
          };

          checks = {
            inherit
              bevy-clicker
              cargo-clippy
              cargo-doc
              llvm-cov
              llvm-cov-text
              ;
            formatting = treefmtEval.config.build.check self;
          };

          devShells.default = pkgs.mkShell rec {
            packages = [
              # Rust
              rust

              # Nix
              pkgs.nil
            ] ++ dependencies;

            LD_LIBRARY_PATH = lib.makeLibraryPath packages;

            shellHook = ''
              export PS1="\n[nix-shell:\w]$ "
            '';
          };
        }
      );
}
