{ inputs, ... }:
{
  imports = [
    inputs.treefmt-nix.flakeModule
  ];

  perSystem = { config, self', inputs', pkgs, system, ... }: {
    # Formatter configuration
    treefmt.config = {
      projectRootFile = "flake.nix";
      programs = {
        nixpkgs-fmt.enable = true;
        shellcheck.enable = true;
        shfmt.enable = true;
      };
      settings.formatter = {
        shellcheck = {
          options = [ "-e" "SC2148" ]; # Ignore shebang warnings for embedded scripts
        };
        shfmt = {
          options = [ "-i" "2" "-ci" ];
        };
      };
    };

    # Make formatter available as package
    packages.formatter = config.treefmt.build.wrapper;
  };
}