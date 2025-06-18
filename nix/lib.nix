{ inputs, ... }:
{
  flake = {
    lib = {
      # Shared hardware detection script
      hardwareDetectionScript = pkgs: ''
        # Detect NVMe serial with multiple fallback methods
        detect_nvme_serial() {
          local NVME_SERIAL=""
          
          if command -v ${pkgs.nvme-cli}/bin/nvme >/dev/null 2>&1; then
            # Method 1: nvme id-ctrl (most reliable)
            for nvme_dev in /dev/nvme*n1; do
              if [ -e "$nvme_dev" ]; then
                NVME_SERIAL=$(${pkgs.nvme-cli}/bin/nvme id-ctrl "$nvme_dev" 2>/dev/null | grep '^sn' | awk '{print $3}' || echo "")
                if [ -n "$NVME_SERIAL" ] && [ "$NVME_SERIAL" != "---------------------" ]; then
                  break
                fi
              fi
            done
            
            # Method 2: nvme list fallback
            if [ -z "$NVME_SERIAL" ] || [ "$NVME_SERIAL" = "---------------------" ]; then
              NVME_SERIAL=$(${pkgs.nvme-cli}/bin/nvme list 2>/dev/null | awk 'NR>1 && $2 != "---------------------" {print $2; exit}' || echo "")
            fi
          fi
          
          # Method 3: sysfs fallback
          if [ -z "$NVME_SERIAL" ] || [ "$NVME_SERIAL" = "---------------------" ]; then
            if [ -f /sys/class/nvme/nvme0/serial ]; then
              NVME_SERIAL=$(cat /sys/class/nvme/nvme0/serial 2>/dev/null || echo "")
            fi
          fi
          
          # Final fallback
          if [ -z "$NVME_SERIAL" ] || [ "$NVME_SERIAL" = "---------------------" ]; then
            NVME_SERIAL="no-nvme-detected"
          fi
          
          echo "$NVME_SERIAL"
        }
        
        # Detect MAC address
        detect_mac_address() {
          local MAC_ADDRESS=""
          
          if command -v ${pkgs.iproute2}/bin/ip >/dev/null 2>&1; then
            MAC_ADDRESS=$(${pkgs.iproute2}/bin/ip link show | awk '/ether/ {print $2; exit}' || echo "")
          fi
          
          if [ -z "$MAC_ADDRESS" ]; then
            MAC_ADDRESS="00:00:00:00:00:00"
          fi
          
          echo "$MAC_ADDRESS"
        }
      '';

      # Shared ACPI template generation
      generateAcpiTemplate = { nvmeSerial, macAddress }: ''
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

      # Function to generate hardware info with custom values
      generateHwInfo = { system, nvmeSerial ? null, macAddress ? null }:
        inputs.self.packages.${system}.generateHwInfo {
          inherit nvmeSerial macAddress;
        };


    };
  };
}
