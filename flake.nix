{
  description = "QEMU ACPI Hardware Info - Nix Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      imports = [
        ./packages/default.nix
        ./modules/default.nix
        ./nix/devshell.nix
        ./nix/formatter.nix
        ./nix/lib.nix
        ./tests/default.nix
      ];

      perSystem = { config, self', inputs', pkgs, system, ... }: {
        apps = {
          # MicroVM runner app
          microvm-run = {
            type = "app";
            program = let
              example = import ./examples/microvm.nix { 
                self = inputs.self; 
                inherit (inputs) nixpkgs microvm; 
              };
              nixosSystem = inputs.nixpkgs.lib.nixosSystem {
                inherit system;
                modules = [
                  example
                ];
              };
              runner = nixosSystem.config.microvm.declaredRunner;
            in "${runner}/bin/microvm-run";
          };
        };
      };
    };
}
