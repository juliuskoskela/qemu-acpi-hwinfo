{
  description = "QEMU ACPI Hardware Info - Nix Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, microvm }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Derivation to generate ACPI hardware info table
        generateHwInfo = { nvmeSerial ? null, macAddress ? null }:
          pkgs.stdenv.mkDerivation rec {
            pname = "qemu-acpi-hwinfo";
            version = "1.0.0";

            src = ./.;

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
          default = generateHwInfo {};
          hwinfo = generateHwInfo {};
        };

        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            acpica-tools
            qemu
            iproute2
            nvme-cli
          ];
        };


      }
    ) // {
      # NixOS module
      nixosModules = {
        acpi-hwinfo = { config, lib, pkgs, ... }:
          with lib;
          let
            cfg = config.services.acpi-hwinfo;
          in {
            options.services.acpi-hwinfo = {
              enable = mkEnableOption "ACPI hardware info for VMs";

              nvmeSerial = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Override NVMe serial number";
              };

              macAddress = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Override MAC address";
              };

              hwinfoPath = mkOption {
                type = types.path;
                readOnly = true;
                description = "Path to the generated hwinfo.aml file";
              };
            };

            config = mkIf cfg.enable {
              services.acpi-hwinfo.hwinfoPath =
                let
                  hwinfo = self.packages.${pkgs.system}.generateHwInfo {
                    nvmeSerial = cfg.nvmeSerial;
                    macAddress = cfg.macAddress;
                  };
                in "${hwinfo}/hwinfo.aml";
            };
          };

        # Guest module for reading hardware info
        guest = { config, lib, pkgs, ... }:
          with lib;
          let
            cfg = config.services.acpi-hwinfo-guest;

            readHwInfoScript = pkgs.writeShellScriptBin "read-hwinfo" ''
              #!/bin/bash
              echo "Reading ACPI hardware info..."
              sudo ${pkgs.util-linux}/bin/strings /sys/firmware/acpi/tables/SSDT* 2>/dev/null | \
                ${pkgs.gnugrep}/bin/grep -A 1 -B 1 "NVME_SERIAL\|MAC_ADDRESS" || \
                echo "No hardware info found in ACPI tables"
            '';

          in {
            options.services.acpi-hwinfo-guest = {
              enable = mkEnableOption "ACPI hardware info reader for guest VMs";
            };

            config = mkIf cfg.enable {
              environment.systemPackages = [ readHwInfoScript ];

              # Create a systemd service to read hwinfo on boot
              systemd.services.acpi-hwinfo-reader = {
                description = "Read ACPI Hardware Info";
                wantedBy = [ "multi-user.target" ];
                after = [ "network.target" ];
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = "${readHwInfoScript}/bin/read-hwinfo";
                  RemainAfterExit = true;
                };
              };
            };
          };
      };

      # MicroVM configuration template
      lib = {
        # Function to generate hardware info with custom values
        generateHwInfo = { system, nvmeSerial ? null, macAddress ? null }:
          let
            pkgs = nixpkgs.legacyPackages.${system};
            generateHwInfo = { nvmeSerial ? null, macAddress ? null }:
              pkgs.stdenv.mkDerivation rec {
                pname = "qemu-acpi-hwinfo";
                version = "1.0.0";

                src = ./.;

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
          in generateHwInfo { inherit nvmeSerial macAddress; };

        mkMicroVMWithHwInfo = { system, nvmeSerial ? null, macAddress ? null, ... }@args:
          let
            pkgs = nixpkgs.legacyPackages.${system};
            hwinfo = self.lib.generateHwInfo {
              inherit system nvmeSerial macAddress;
            };
          in {
            imports = [
              microvm.nixosModules.microvm
              self.nixosModules.guest
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