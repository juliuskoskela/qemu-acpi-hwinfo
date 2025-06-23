{
  description = "QEMU ACPI hardware info embedding system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./nix/flake-module.nix
        ./packages/flake-module.nix
        ./modules/flake-module.nix
      ];
      
      systems = [ "x86_64-linux" "aarch64-linux" ];
    };
}