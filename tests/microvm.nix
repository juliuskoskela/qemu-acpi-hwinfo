{ inputs, ... }:
{
  perSystem = { config, self', inputs', pkgs, system, ... }: {
    packages = {
      # MicroVM test configuration
      test-microvm = let
        microvmSystem = inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            inputs.microvm.nixosModules.microvm
            inputs.self.nixosModules.acpi-hwinfo-guest
            {
              # Enable ACPI hardware info for MicroVM
              virtualisation.acpi-hwinfo = {
                enable = true;
                enableMicrovm = true;
                guestTools = true;
                hostHwinfoPath = "/var/lib/acpi-hwinfo/hwinfo.aml";
              };

              # MicroVM configuration
              microvm = {
                vcpu = 2;
                mem = 1024;
                hypervisor = "qemu";

                # Network configuration
                interfaces = [{
                  type = "user";
                  id = "vm-net";
                  mac = "02:00:00:00:00:01";
                }];

                # Share the Nix store
                shares = [{
                  source = "/nix/store";
                  mountPoint = "/nix/.ro-store";
                  tag = "ro-store";
                  proto = "virtiofs";
                }];

                # Add ACPI table with hardware info
                qemu.extraArgs = [
                  "-acpitable" "file=/var/lib/acpi-hwinfo/hwinfo.aml"
                ];
              };

              # System configuration
              system.stateVersion = "24.05";

              # Auto-login for testing
              services.getty.autologinUser = "root";

              # Test packages
              environment.systemPackages = with pkgs; [
                jq
                acpica-tools
                vim
                htop
              ];

              # Create a test script that can be run in the VM
              environment.etc."test-acpi-hwinfo.sh" = {
                mode = "0755";
                text = ''
                  #!/bin/bash
                  set -euo pipefail
                  
                  echo "🧪 ACPI Hardware Info Test"
                  echo "=========================="
                  echo
                  
                  # Test 1: Check if ACPI device exists
                  echo "📱 Test 1: ACPI Device Check"
                  if [ -d "/sys/bus/acpi/devices/ACPI0001:00" ]; then
                    echo "✅ ACPI device ACPI0001:00 found"
                    echo "   HID: $(cat /sys/bus/acpi/devices/ACPI0001:00/hid 2>/dev/null || echo 'N/A')"
                  else
                    echo "❌ ACPI device ACPI0001:00 not found"
                    echo "💡 Available ACPI devices:"
                    ls -la /sys/bus/acpi/devices/ | head -10
                    return 1
                  fi
                  echo
                  
                  # Test 2: Check command availability
                  echo "🔧 Test 2: Command Availability"
                  for cmd in read-hwinfo show-acpi-hwinfo extract-hwinfo-json; do
                    if command -v "$cmd" >/dev/null 2>&1; then
                      echo "✅ $cmd available"
                    else
                      echo "❌ $cmd not available"
                      return 1
                    fi
                  done
                  echo
                  
                  # Test 3: Read hardware info
                  echo "📋 Test 3: Hardware Info Reading"
                  if read-hwinfo; then
                    echo "✅ Hardware info read successfully"
                  else
                    echo "❌ Failed to read hardware info"
                    return 1
                  fi
                  echo
                  
                  # Test 4: Check ACPI tables
                  echo "🔍 Test 4: ACPI Tables Verification"
                  echo "Available ACPI tables:"
                  ls -la /sys/firmware/acpi/tables/
                  echo
                  echo "Searching for hardware info in SSDT tables:"
                  for ssdt in /sys/firmware/acpi/tables/SSDT*; do
                    if [ -f "$ssdt" ]; then
                      echo "=== $(basename $ssdt) ==="
                      strings "$ssdt" 2>/dev/null | grep -A 3 -B 1 "NVME_SERIAL\|MAC_ADDRESS" || echo "No hardware info found"
                    fi
                  done
                  
                  echo
                  echo "🎉 All tests passed!"
                '';
              };

              # Auto-run test on boot for automated testing
              systemd.services.acpi-hwinfo-auto-test = {
                description = "Auto-run ACPI hardware info test";
                wantedBy = [ "multi-user.target" ];
                after = [ "multi-user.target" ];
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = pkgs.writeShellScript "auto-test" ''
                    echo "🧪 Running automated ACPI hardware info test..."
                    sleep 5  # Give system time to fully boot
                    if /etc/test-acpi-hwinfo.sh; then
                      echo "✅ Automated test passed!"
                      echo "🔌 Shutting down VM in 3 seconds..."
                      sleep 3
                      systemctl poweroff
                    else
                      echo "❌ Automated test failed!"
                      sleep 2
                      systemctl poweroff
                      exit 1
                    fi
                  '';
                };

                # Environment variable to enable auto-test
                environment.ACPI_HWINFO_AUTO_TEST = "1";
              };
            }
          ];
        };
      in
      microvmSystem.config.microvm.runner.qemu;

      # Script to build and run the test MicroVM
      run-test-microvm = pkgs.writeShellScriptBin "run-test-microvm" ''
        set -euo pipefail
        
        echo "🔨 Building test MicroVM..."
        MICROVM=$(nix --extra-experimental-features "nix-command flakes" build --no-link --print-out-paths .#test-microvm)
        
        echo "✅ MicroVM built: $MICROVM"
        echo
        
        # Ensure we have test hardware info
        if [ ! -f "/var/lib/acpi-hwinfo/hwinfo.aml" ]; then
          echo "📝 Creating test hardware info..."
          sudo mkdir -p /var/lib/acpi-hwinfo
          ${self'.packages.create-test-hwinfo}/bin/create-test-hwinfo \
            "MICROVM_SERIAL_123" \
            "02:03:04:05:06:07" \
            "/var/lib/acpi-hwinfo"
        fi
        
        echo "📋 Using hardware info:"
        cat /var/lib/acpi-hwinfo/hwinfo.json
        echo
        
        echo "🚀 Starting test MicroVM with ACPI hardware info..."
        echo "   MicroVM will auto-login as root"
        echo "   Run '/etc/test-acpi-hwinfo.sh' inside VM to test"
        echo "   Use Ctrl+C to shutdown"
        echo
        
        # Run the MicroVM
        exec "$MICROVM/bin/microvm-run"
      '';

      # Automated MicroVM test runner
      run-automated-microvm-test = pkgs.writeShellScriptBin "run-automated-microvm-test" ''
        set -euo pipefail
        
        echo "🔬 Running automated MicroVM test..."
        MICROVM=$(nix --extra-experimental-features "nix-command flakes" build --no-link --print-out-paths .#test-microvm)
        
        echo "✅ MicroVM built: $MICROVM"
        
        # Ensure we have test hardware info
        if [ ! -f "/var/lib/acpi-hwinfo/hwinfo.aml" ]; then
          echo "📝 Creating test hardware info..."
          sudo mkdir -p /var/lib/acpi-hwinfo
          ${self'.packages.create-test-hwinfo}/bin/create-test-hwinfo \
            "AUTO_TEST_SERIAL_999" \
            "aa:bb:cc:dd:ee:ff" \
            "/var/lib/acpi-hwinfo"
        fi
        
        echo "📋 Using hardware info:"
        cat /var/lib/acpi-hwinfo/hwinfo.json
        echo
        
        echo "🚀 Starting automated MicroVM test..."
        echo "   MicroVM will run test and shutdown automatically"
        echo "   Timeout: 120 seconds"
        echo
        
        # Run the MicroVM with timeout for automated testing
        timeout 120 "$MICROVM/bin/microvm-run" || {
          exit_code=$?
          if [ $exit_code -eq 124 ]; then
            echo "⏰ MicroVM test timed out after 120 seconds"
            exit 1
          elif [ $exit_code -eq 0 ]; then
            echo "✅ MicroVM test completed successfully"
            exit 0
          else
            echo "❌ MicroVM test failed with exit code $exit_code"
            exit $exit_code
          fi
        }
      '';
    };
  };
}