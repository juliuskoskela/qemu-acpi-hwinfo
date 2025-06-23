{ self, lib, inputs, ... }:

{
  flake = {
    nixosModules = {
      default = ./default.nix;
      guest = ./default.nix;
      host = ./host.nix;
      test-vm = ./test-vm.nix;
    };
    
    nixosConfigurations = {
      test-vm = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.guest
          self.nixosModules.test-vm
        ];
      };
    };
  };
}