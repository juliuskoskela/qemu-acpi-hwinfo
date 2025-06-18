{
  description = "QEMU ACPI hardware info embedding system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" ];
      
      perSystem = { pkgs, ... }: {
        packages = {
          # Generate hardware info and create ACPI table
          generate-hwinfo = pkgs.writeShellScriptBin "generate-hwinfo" ''
            set -euo pipefail
            
            HWINFO_DIR="''${1:-/var/lib/acpi-hwinfo}"
            mkdir -p "$HWINFO_DIR"
            
            # Detect NVMe serial
            NVME_SERIAL="no-nvme-detected"
            if command -v ${pkgs.nvme-cli}/bin/nvme >/dev/null 2>&1; then
              for nvme_dev in /dev/nvme*n1; do
                if [ -e "$nvme_dev" ]; then
                  NVME_SERIAL=$(${pkgs.nvme-cli}/bin/nvme id-ctrl "$nvme_dev" 2>/dev/null | grep '^sn' | awk '{print $3}' || echo "")
                  [ -n "$NVME_SERIAL" ] && [ "$NVME_SERIAL" != "---------------------" ] && break
                fi
              done
            fi
            
            # Detect MAC address
            MAC_ADDRESS=$(${pkgs.iproute2}/bin/ip link show 2>/dev/null | awk '/ether/ {print $2; exit}' || echo "00:00:00:00:00:00")
            
            # Generate ASL file
            cat >"$HWINFO_DIR/hwinfo.asl" <<EOF
            DefinitionBlock ("hwinfo.aml", "SSDT", 2, "HWINFO", "HWINFO", 0x00000001)
            {
                Scope (\_SB)
                {
                    Device (HWIN)
                    {
                        Name (_HID, "ACPI0001")
                        Name (_UID, 0x00)
                        Method (GHWI, 0, NotSerialized)
                        {
                            Return (Package (0x04)
                            {
                                "NVME_SERIAL", "$NVME_SERIAL", 
                                "MAC_ADDRESS", "$MAC_ADDRESS"
                            })
                        }
                        Method (_STA, 0, NotSerialized) { Return (0x0F) }
                    }
                }
            }
            EOF
            
            # Compile to AML
            cd "$HWINFO_DIR" && ${pkgs.acpica-tools}/bin/iasl hwinfo.asl >/dev/null 2>&1
            echo "Generated ACPI hardware info in $HWINFO_DIR"
          '';

          # Read hardware info from ACPI in guest
          read-hwinfo = pkgs.writeShellScriptBin "read-hwinfo" ''
            set -euo pipefail
            
            ACPI_DEVICE="/sys/bus/acpi/devices/ACPI0001:00"
            [ ! -d "$ACPI_DEVICE" ] && { echo "ACPI device not found"; exit 1; }
            
            # Extract hardware info from ACPI tables
            for table in /sys/firmware/acpi/tables/SSDT*; do
              if ${pkgs.binutils}/bin/strings "$table" 2>/dev/null | grep -q "HWINFO"; then
                ${pkgs.binutils}/bin/strings "$table" | grep -A1 -E "(NVME_SERIAL|MAC_ADDRESS)" | grep -v -E "(NVME_SERIAL|MAC_ADDRESS)" | head -2
                break
              fi
            done
          '';


        };

        # Simple dev shell
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ nvme-cli acpica-tools qemu ];
        };
      };

      flake.nixosModules.default = ./modules;
    };
}