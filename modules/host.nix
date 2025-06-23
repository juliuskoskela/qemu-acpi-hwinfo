{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.acpi-hwinfo;
  generate-hwinfo = pkgs.callPackage ../packages/generate-hwinfo {};
in
{
  options.services.acpi-hwinfo = {
    enable = mkEnableOption "ACPI hardware info generation for VMs";

    outputDir = mkOption {
      type = types.path;
      default = "/var/lib/acpi-hwinfo";
      description = "Directory where ACPI hardware info files will be generated";
    };
  };

  config = mkIf cfg.enable {
    # Create the output directory
    systemd.tmpfiles.rules = [
      "d ${cfg.outputDir} 0755 root root -"
    ];

    # Systemd service to generate hardware info
    systemd.services.acpi-hwinfo-generate = {
      description = "Generate ACPI hardware info for VMs";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.writeShellScript "generate-acpi-hwinfo" ''
          set -euo pipefail
          
          # Use our generate-hwinfo package
          ${lib.getExe generate-hwinfo} ${cfg.outputDir}
          
          # Also create a JSON metadata file with generation timestamp
          cat > ${cfg.outputDir}/metadata.json <<EOF
          {
            "generated": "$(date -Iseconds)",
            "host": "$(hostname)",
            "outputDir": "${cfg.outputDir}"
          }
          EOF
          
          echo "Generated ACPI hardware info in ${cfg.outputDir}"
        ''}";
      };
    };

    # Add generate-hwinfo to system packages
    environment.systemPackages = [ generate-hwinfo ];
  };
}