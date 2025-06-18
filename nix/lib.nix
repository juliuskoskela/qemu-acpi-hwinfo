{ inputs, ... }:
{
  flake = {
    lib = {
      # Shared hardware detection logic - used across multiple packages
      # This ensures consistent hardware detection behavior across all tools
      hardwareDetectionScript = pkgs: ''
        # Detect NVMe serial with multiple fallback methods
        # Returns the first valid NVMe serial found, or "no-nvme-detected" if none found
        detect_nvme_serial() {
          local NVME_SERIAL=""
          local debug_mode="''${ACPI_HWINFO_DEBUG:-false}"
          
          [ "$debug_mode" = "true" ] && echo "🔍 Debug: Starting NVMe detection..." >&2
          
          # Method 1: nvme id-ctrl (most reliable for getting actual serial)
          if command -v ${pkgs.nvme-cli}/bin/nvme >/dev/null 2>&1; then
            [ "$debug_mode" = "true" ] && echo "🔍 Debug: Trying nvme id-ctrl method..." >&2
            for nvme_dev in /dev/nvme*n1; do
              if [ -e "$nvme_dev" ]; then
                [ "$debug_mode" = "true" ] && echo "🔍 Debug: Checking device $nvme_dev..." >&2
                NVME_SERIAL=$(${pkgs.nvme-cli}/bin/nvme id-ctrl "$nvme_dev" 2>/dev/null | grep '^sn' | awk '{print $3}' || echo "")
                if [ -n "$NVME_SERIAL" ] && [ "$NVME_SERIAL" != "---------------------" ]; then
                  [ "$debug_mode" = "true" ] && echo "🔍 Debug: Found serial via id-ctrl: $NVME_SERIAL" >&2
                  break
                fi
              fi
            done
            
            # Method 2: nvme list fallback (with proper separator filtering)
            if [ -z "$NVME_SERIAL" ] || [ "$NVME_SERIAL" = "---------------------" ]; then
              [ "$debug_mode" = "true" ] && echo "🔍 Debug: Trying nvme list method..." >&2
              NVME_SERIAL=$(${pkgs.nvme-cli}/bin/nvme list 2>/dev/null | awk 'NR>1 && $2 != "---------------------" {print $2; exit}' || echo "")
              [ "$debug_mode" = "true" ] && [ -n "$NVME_SERIAL" ] && echo "🔍 Debug: Found serial via list: $NVME_SERIAL" >&2
            fi
          fi
          
          # Method 3: sysfs fallback
          if [ -z "$NVME_SERIAL" ] || [ "$NVME_SERIAL" = "---------------------" ]; then
            [ "$debug_mode" = "true" ] && echo "🔍 Debug: Trying sysfs method..." >&2
            if [ -f /sys/class/nvme/nvme0/serial ]; then
              NVME_SERIAL=$(cat /sys/class/nvme/nvme0/serial 2>/dev/null || echo "")
              [ "$debug_mode" = "true" ] && [ -n "$NVME_SERIAL" ] && echo "🔍 Debug: Found serial via sysfs: $NVME_SERIAL" >&2
            fi
          fi
          
          # Final fallback
          if [ -z "$NVME_SERIAL" ] || [ "$NVME_SERIAL" = "---------------------" ]; then
            NVME_SERIAL="no-nvme-detected"
            [ "$debug_mode" = "true" ] && echo "🔍 Debug: No NVMe detected, using fallback" >&2
          fi
          
          echo "$NVME_SERIAL"
        }
        
        # Detect MAC address of the first ethernet interface
        # Returns the first MAC address found, or "00:00:00:00:00:00" if none found
        detect_mac_address() {
          local MAC_ADDRESS=""
          local debug_mode="''${ACPI_HWINFO_DEBUG:-false}"
          
          [ "$debug_mode" = "true" ] && echo "🔍 Debug: Starting MAC address detection..." >&2
          
          if command -v ${pkgs.iproute2}/bin/ip >/dev/null 2>&1; then
            MAC_ADDRESS=$(${pkgs.iproute2}/bin/ip link show | awk '/ether/ {print $2; exit}' || echo "")
            [ "$debug_mode" = "true" ] && [ -n "$MAC_ADDRESS" ] && echo "🔍 Debug: Found MAC via ip: $MAC_ADDRESS" >&2
          fi
          
          if [ -z "$MAC_ADDRESS" ]; then
            MAC_ADDRESS="00:00:00:00:00:00"
            [ "$debug_mode" = "true" ] && echo "🔍 Debug: No MAC detected, using fallback" >&2
          fi
          
          echo "$MAC_ADDRESS"
        }
        
        # Validate hardware info format
        # Usage: validate_hardware_info "$nvme_serial" "$mac_address"
        validate_hardware_info() {
          local nvme_serial="$1"
          local mac_address="$2"
          local errors=0
          
          # Validate MAC address format (basic check)
          if [[ ! "$mac_address" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
            echo "❌ Error: Invalid MAC address format: $mac_address" >&2
            echo "   Expected format: XX:XX:XX:XX:XX:XX" >&2
            errors=$((errors + 1))
          fi
          
          # Validate NVMe serial (basic check - not empty and reasonable length)
          if [ -z "$nvme_serial" ]; then
            echo "❌ Error: NVMe serial is empty" >&2
            errors=$((errors + 1))
          elif [ ''${#nvme_serial} -gt 50 ]; then
            echo "⚠️  Warning: NVMe serial is unusually long (''${#nvme_serial} chars): $nvme_serial" >&2
          fi
          
          return $errors
        }
      '';

      # Generate ACPI ASL content with hardware info
      generateAcpiAsl = { nvmeSerial, macAddress }: ''
        DefinitionBlock ("hwinfo.aml", "SSDT", 2, "HWINFO", "HWINFO", 0x00000001)
        {
            Scope (\_SB)
            {
                Device (HWIN)
                {
                    Name (_HID, "ACPI0001")
                    Name (_UID, 0x00)
                    Name (_STR, Unicode ("Hardware Info Device"))
                    
                    Method (GHWI, 0, NotSerialized)
                    {
                        Return (Package (0x04)
                        {
                            "NVME_SERIAL", 
                            "${nvmeSerial}", 
                            "MAC_ADDRESS", 
                            "${macAddress}"
                        })
                    }
                    
                    Method (_STA, 0, NotSerialized)
                    {
                        Return (0x0F)
                    }
                }
            }
        }
      '';

      # Generate JSON metadata with hardware info
      generateHwInfoJson = { nvmeSerial, macAddress }: ''
        {
          "nvme_serial": "${nvmeSerial}",
          "mac_address": "${macAddress}",
          "generated": "$(date -Iseconds)"
        }
      '';

      # Function to generate hardware info with custom values
      generateHwInfo = { system, nvmeSerial ? null, macAddress ? null }:
        inputs.self.packages.${system}.generateHwInfo {
          inherit nvmeSerial macAddress;
        };

      # Function to create a MicroVM configuration with hardware info
      mkMicroVMWithHwInfo = { system, nvmeSerial ? null, macAddress ? null, ... }@args:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
          hwinfo = inputs.self.lib.generateHwInfo {
            inherit system nvmeSerial macAddress;
          };
        in
        {
          imports = [
            inputs.microvm.nixosModules.microvm
            inputs.self.nixosModules.guest
          ];

          services.acpi-hwinfo-guest.enable = true;

          microvm = {
            enable = true;

            qemu = {
              extraArgs = [
                "-acpitable"
                "file=${hwinfo}/hwinfo.aml"
              ];
            };

            # Default VM configuration
            vcpu = 2;
            mem = 2048;

            interfaces = [{
              type = "user";
              id = "vm-net";
              mac = "02:00:00:00:00:01";
            }];

            shares = [{
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
              tag = "ro-store";
              proto = "virtiofs";
            }];
          };

          # Basic system configuration
          system.stateVersion = "24.05";

          # Enable guest services
          services.getty.autologinUser = "root";

          # Add some basic packages
          environment.systemPackages = with pkgs; [
            vim
            htop
            curl
          ];
        };
    };
  };
}
