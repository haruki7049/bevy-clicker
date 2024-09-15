{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    rust-overlay.url = "github:oxalica/rust-overlay";
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      imports = [
        inputs.treefmt-nix.flakeModule
      ];
      perSystem =
        {
          pkgs,
          lib,
          system,
          inputs',
          self',
          ...
        }:
        let
          rust = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain rust;
          overlays = [ inputs.rust-overlay.overlays.default ];
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
          src = lib.cleanSource ./.;
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
            cargoClippyExtraArgs = "--verbose -- --deny warning";
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
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system overlays;
          };

          treefmt = {
            projectRootFile = "flake.nix";
            programs.nixfmt.enable = true;
            programs.rustfmt.enable = true;
            programs.taplo.enable = true;
            programs.actionlint.enable = true;
          };

          packages = {
            inherit bevy-clicker llvm-cov llvm-cov-text;
            default = bevy-clicker;
            doc = cargo-doc;
          };

          checks = {
            inherit
              bevy-clicker
              cargo-clippy
              cargo-doc
              llvm-cov
              llvm-cov-text
              ;
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
        };
    };
}
