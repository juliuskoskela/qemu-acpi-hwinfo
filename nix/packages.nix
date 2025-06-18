{ inputs, ... }:
{
  perSystem = { config, self', inputs', pkgs, system, ... }: 
  let
    generateHwInfo = { nvmeSerial ? null, macAddress ? null }:
        pkgs.stdenv.mkDerivation rec {
          pname = "qemu-acpi-hwinfo";
          version = "1.0.0";

          src = ../.;

          nativeBuildInputs = with pkgs; [
            acpica-tools  # provides iasl
            iproute2      # for ip command
            nvme-cli      # for nvme command
            bash
          ];

          buildInputs = with pkgs; [
            acpica-tools
          ];

          buildPhase = ''
            # Get hardware info with fallbacks to provided values
            get_nvme_serial() {
              if [ -n "${toString nvmeSerial}" ]; then
                echo "${toString nvmeSerial}"
              elif command -v nvme >/dev/null 2>&1 && [ -e /dev/nvme0n1 ]; then
                nvme id-ctrl /dev/nvme0n1 2>/dev/null | grep '^sn' | awk '{print $3}' || echo "UNKNOWN"
              elif [ -f "/sys/class/nvme/nvme0/serial" ]; then
                cat /sys/class/nvme/nvme0/serial 2>/dev/null || echo "UNKNOWN"
              else
                echo "UNKNOWN"
              fi
            }

            get_mac_address() {
              if [ -n "${toString macAddress}" ]; then
                echo "${toString macAddress}"
              else
                ip link show 2>/dev/null | grep -E "link/ether" | head -1 | awk '{print $2}' 2>/dev/null || echo "00:00:00:00:00:00"
              fi
            }

            NVME_SERIAL=$(get_nvme_serial)
            MAC_ADDRESS=$(get_mac_address)

            echo "Detected hardware:"
            echo "  NVMe Serial: $NVME_SERIAL"
            echo "  MAC Address: $MAC_ADDRESS"

            # Create ACPI SSDT table
            cat > hwinfo.asl << EOF
            /*
             * Hardware Info ACPI Table
             * Generated: $(date)
             */
            DefinitionBlock ("hwinfo.aml", "SSDT", 2, "QEMU", "HWINFO", 1)
            {
                Scope (\\_SB)
                {
                    Device (HWIN)
                    {
                        Name (_HID, "ACPI0001")
                        Name (_UID, 0)
                        Name (_STR, Unicode("Hardware Info Device"))

                        Method (GHWI, 0, NotSerialized)
                        {
                            Return (Package (0x04) {
                                "NVME_SERIAL",
                                "$NVME_SERIAL",
                                "MAC_ADDRESS",
                                "$MAC_ADDRESS"
                            })
                        }

                        Method (_STA, 0, NotSerialized)
                        {
                            Return (0x0F)  // Device present and enabled
                        }
                    }
                }
            }
            EOF

            # Compile ACPI table
            echo "Compiling ACPI table..."
            iasl hwinfo.asl

            if [ ! -f hwinfo.aml ]; then
              echo "Error: Failed to compile ACPI table"
              exit 1
            fi
          '';

          installPhase = ''
            mkdir -p $out
            cp hwinfo.aml $out/
            cp hwinfo.asl $out/

            # Create a metadata file with the hardware info
            cat > $out/hwinfo.json << EOF
            {
              "nvme_serial": "$NVME_SERIAL",
              "mac_address": "$MAC_ADDRESS",
              "generated": "$(date -Iseconds)"
            }
            EOF
          '';

          meta = with pkgs.lib; {
            description = "ACPI hardware info table for QEMU VMs";
            license = licenses.mit;
            platforms = platforms.linux;
          };
        };
  in {
    packages = {
      default = generateHwInfo { };
      hwinfo = generateHwInfo { };
      inherit generateHwInfo;
    };
  };
}