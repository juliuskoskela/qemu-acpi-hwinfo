{ lib, inputs, self, ... }:

{
  perSystem = { config, self', inputs', pkgs, system, ... }: {
    packages = {
      generate-hwinfo = pkgs.callPackage ./generate-hwinfo {};
      read-hwinfo = pkgs.callPackage ./read-hwinfo {};
      test-vm = pkgs.callPackage ./test-vm { inherit (self'.packages) generate-hwinfo; };
    };
  };
}