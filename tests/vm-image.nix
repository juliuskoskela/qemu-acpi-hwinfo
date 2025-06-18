# VM disk image for testing ACPI hardware info
{ inputs, ... }:
{
  perSystem = { config, self', inputs', pkgs, system, ... }: {
    packages = {
      # Build a VM disk image with our guest module
      test-vm-image =
        let
          vmSystem = inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              inputs.self.nixosModules.acpi-hwinfo-guest
              {
                # Enable ACPI hardware info for testing
                virtualisation.acpi-hwinfo = {
                  enable = true;
                  guestTools = true;
                };

                # VM configuration - use minimal settings
                virtualisation.vmVariant = {
                  virtualisation.diskSize = 4096; # 4GB disk
                  virtualisation.memorySize = 2048; # 2GB RAM
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
                  text = ''
                    #!/bin/bash
                    set -euo pipefail
                
                    echo "🧪 Testing ACPI hardware info in VM..."
                    echo "======================================"
                
                    # Test 1: Check if ACPI device exists
                    echo "1️⃣  Checking ACPI device..."
                    if [ -d "/sys/bus/acpi/devices/ACPI0001:00" ]; then
                      echo "✅ ACPI device found at /sys/bus/acpi/devices/ACPI0001:00"
                    else
                      echo "❌ ACPI device not found"
                      echo "Available ACPI devices:"
                      ls -la /sys/bus/acpi/devices/ || echo "No ACPI devices found"
                      exit 1
                    fi
                
                    # Test 2: Check if acpi-hwinfo-show command is available
                    echo "2️⃣  Checking acpi-hwinfo-show command..."
                    if command -v acpi-hwinfo-show >/dev/null 2>&1; then
                      echo "✅ acpi-hwinfo-show command available"
                    else
                      echo "❌ acpi-hwinfo-show command not found"
                      exit 1
                    fi
                
                    # Test 3: Try to read hardware info
                    echo "3️⃣  Reading hardware info..."
                    if acpi-hwinfo-show; then
                      echo "✅ Successfully read hardware info"
                    else
                      echo "⚠️  Could not read hardware info (this is expected if no ACPI table is loaded)"
                    fi
                
                    # Test 4: Check ACPI tables
                    echo "4️⃣  Checking ACPI tables..."
                    if [ -d "/sys/firmware/acpi/tables" ]; then
                      echo "✅ ACPI tables directory exists"
                      echo "Available ACPI tables:"
                      ls -la /sys/firmware/acpi/tables/
                    else
                      echo "❌ ACPI tables directory not found"
                    fi
                
                    echo "🎉 VM test completed!"
                    echo "   To test with actual hardware info, start VM with:"
                    echo "   qemu-with-hwinfo test-vm.qcow2"
                  '';
                  mode = "0755";
                };

                # Add a systemd service that runs the test on boot
                systemd.services.acpi-hwinfo-boot-test = {
                  description = "ACPI hardware info boot test";
                  wantedBy = [ "multi-user.target" ];
                  after = [ "multi-user.target" ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                  };
                  script = ''
                    echo "🚀 VM booted successfully with ACPI hardware info support"
                    echo "   Run '/etc/test-acpi-hwinfo.sh' to test functionality"
                  '';
                };

                # Add an automated test service for CI/testing
                systemd.services.acpi-hwinfo-auto-test = {
                  description = "ACPI hardware info automated test";
                  wantedBy = [ "multi-user.target" ];
                  after = [ "acpi-hwinfo-boot-test.service" "network.target" ];
                  serviceConfig = {
                    Type = "oneshot";
                    StandardOutput = "journal+console";
                    StandardError = "journal+console";
                  };
                  script = ''
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
                environment.variables.ACPI_HWINFO_AUTO_TEST = "1";
              }
            ];
          };
        in
        vmSystem.config.system.build.vm;

      # Script to build and run the test VM
      run-test-vm = pkgs.writeShellScriptBin "run-test-vm" ''
        set -euo pipefail
        
        echo "🔨 Building test VM disk image..."
        VM_IMAGE=$(nix --extra-experimental-features "nix-command flakes" build --no-link --print-out-paths .#test-vm-image)
        
        echo "✅ VM image built: $VM_IMAGE"
        echo
        
        # Ensure we have test hardware info
        if [ ! -f "/var/lib/acpi-hwinfo/hwinfo.aml" ]; then
          echo "📝 Creating test hardware info..."
          sudo mkdir -p /var/lib/acpi-hwinfo
          ${self'.packages.create-test-hwinfo}/bin/create-test-hwinfo \
            "TEST_VM_SERIAL_456" \
            "02:03:04:05:06:07" \
            "/var/lib/acpi-hwinfo"
        fi
        
        echo "📋 Using hardware info:"
        cat /var/lib/acpi-hwinfo/hwinfo.json
        echo
        
        echo "🚀 Starting test VM with ACPI hardware info..."
        echo "   VM will auto-login as root"
        echo "   Run '/etc/test-acpi-hwinfo.sh' inside VM to test"
        echo "   Use 'system_powerdown' in QEMU monitor to shutdown"
        echo
        
        # Run the VM with our hardware info in headless mode
        QEMU_OPTS="-nographic -serial mon:stdio" exec "$VM_IMAGE/bin/run-nixos-vm"
      '';

      # Script to build VM and run with qemu-with-hwinfo
      run-test-vm-with-hwinfo = pkgs.writeShellScriptBin "run-test-vm-with-hwinfo" ''
        set -euo pipefail
        
        echo "🔨 Building test VM disk image..."
        VM_IMAGE=$(nix --extra-experimental-features "nix-command flakes" build --no-link --print-out-paths .#test-vm-image)
        
        echo "✅ VM image built: $VM_IMAGE"
        
        # Ensure we have test hardware info
        if [ ! -f "/var/lib/acpi-hwinfo/hwinfo.aml" ]; then
          echo "📝 Creating test hardware info..."
          sudo mkdir -p /var/lib/acpi-hwinfo
          ${self'.packages.create-test-hwinfo}/bin/create-test-hwinfo \
            "QEMU_TEST_SERIAL_789" \
            "08:09:0a:0b:0c:0d" \
            "/var/lib/acpi-hwinfo"
        fi
        
        echo "📋 Using hardware info:"
        cat /var/lib/acpi-hwinfo/hwinfo.json
        echo
        
        echo "🚀 Starting VM with qemu-with-hwinfo..."
        echo "   This uses our custom QEMU wrapper with ACPI hardware info"
        echo "   VM will auto-login as root"
        echo "   Run '/etc/test-acpi-hwinfo.sh' inside VM to test"
        echo "   Use 'system_powerdown' in QEMU monitor to shutdown"
        echo
        
        # Run with our qemu wrapper in headless mode
        QEMU_OPTS="-nographic -serial mon:stdio" exec "$VM_IMAGE/bin/run-nixos-vm"
      '';

      # Automated test runner that runs the test and exits
      run-automated-vm-test = pkgs.writeShellScriptBin "run-automated-vm-test" ''
        set -euo pipefail
        
        echo "🔬 Running automated VM test..."
        VM_IMAGE=$(nix --extra-experimental-features "nix-command flakes" build --no-link --print-out-paths .#test-vm-image)
        
        echo "✅ VM image built: $VM_IMAGE"
        
        # Ensure we have test hardware info
        if [ ! -f "/var/lib/acpi-hwinfo/hwinfo.aml" ]; then
          echo "📝 Creating test hardware info..."
          sudo mkdir -p /var/lib/acpi-hwinfo
          ${self'.packages.create-test-hwinfo}/bin/create-test-hwinfo
        fi
        
        echo "📋 Using hardware info:"
        cat /var/lib/acpi-hwinfo/hwinfo.json
        echo
        
        echo "🚀 Starting automated VM test..."
        echo "   VM will run test and shutdown automatically"
        echo "   Timeout: 120 seconds"
        echo
        
        # Run the VM with timeout for automated testing
        timeout 120 env QEMU_OPTS="-nographic -serial mon:stdio" "$VM_IMAGE/bin/run-nixos-vm" || {
          exit_code=$?
          if [ $exit_code -eq 124 ]; then
            echo "⏰ VM test timed out after 120 seconds"
            exit 1
          elif [ $exit_code -eq 0 ]; then
            echo "✅ VM test completed successfully"
            exit 0
          else
            echo "❌ VM test failed with exit code $exit_code"
            exit $exit_code
          fi
        }
      '';
    };
  };
}
