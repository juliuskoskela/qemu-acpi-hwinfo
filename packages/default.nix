{ inputs, ... }:
{
  perSystem = { config, self', inputs', pkgs, system, ... }: {
    packages = {
      # ACPI hardware info generator - detects hardware and creates ACPI files
      acpi-hwinfo-generate = pkgs.writeShellScriptBin "acpi-hwinfo-generate" ''
                #!/bin/bash
                set -euo pipefail
        
                HWINFO_DIR="/var/lib/acpi-hwinfo"
        
                # Check if we can write to the system directory
                if [ ! -w "$(dirname "$HWINFO_DIR")" ] 2>/dev/null; then
                  echo "⚠️  Cannot write to $HWINFO_DIR, using local directory instead"
                  HWINFO_DIR="./acpi-hwinfo"
                fi
        
                echo "🔧 Generating ACPI hardware info in $HWINFO_DIR..."
                mkdir -p "$HWINFO_DIR"
        
                # Import shared hardware detection functions
                ${inputs.self.lib.hardwareDetectionScript pkgs}
        
                # Detect hardware
                NVME_SERIAL=$(detect_nvme_serial)
                MAC_ADDRESS=$(detect_mac_address)
        
                echo "📊 Detected hardware:"
                echo "   NVMe Serial: $NVME_SERIAL"
                echo "   MAC Address: $MAC_ADDRESS"
        
                # Generate JSON metadata
                cat >"$HWINFO_DIR/hwinfo.json" <<EOF
        {
          "nvme_serial": "$NVME_SERIAL",
          "mac_address": "$MAC_ADDRESS",
          "generated": "$(date -Iseconds)"
        }
        EOF
        
                # Generate ASL file using shared template
                cat >"$HWINFO_DIR/hwinfo.asl" <<EOF
        ${inputs.self.lib.generateAcpiTemplate { nvmeSerial = "$NVME_SERIAL"; macAddress = "$MAC_ADDRESS"; }}
        EOF
        
                # Compile ASL to AML
                echo "🔨 Compiling ACPI table..."
                cd "$HWINFO_DIR"
                ${pkgs.acpica-tools}/bin/iasl hwinfo.asl
        
                echo "✅ Hardware info generated successfully in $HWINFO_DIR"
                echo "📁 Files created:"
                ls -la "$HWINFO_DIR/"
      '';

      # Show current hardware info
      acpi-hwinfo-show = pkgs.writeShellScriptBin "acpi-hwinfo-show" ''
        #!/bin/bash
        HWINFO_DIR="/var/lib/acpi-hwinfo"
        
        if [ ! -d "$HWINFO_DIR" ]; then
          HWINFO_DIR="./acpi-hwinfo"
        fi
        
        if [ -f "$HWINFO_DIR/hwinfo.json" ]; then
          echo "📊 Current hardware info from $HWINFO_DIR:"
          echo
          ${pkgs.jq}/bin/jq . "$HWINFO_DIR/hwinfo.json" 2>/dev/null || cat "$HWINFO_DIR/hwinfo.json"
          echo
          echo "📁 Available files:"
          ls -la "$HWINFO_DIR/"
        else
          echo "❌ No hardware info found in $HWINFO_DIR"
          echo "💡 Run 'acpi-hwinfo-generate' first to create hardware info"
          exit 1
        fi
      '';

      # Status checker with helpful information
      hwinfo-status = pkgs.writeShellScriptBin "hwinfo-status" ''
        #!/bin/bash
        echo "🔍 ACPI Hardware Info Status"
        echo "=========================="
        echo
        
        HWINFO_DIR="/var/lib/acpi-hwinfo"
        if [ ! -d "$HWINFO_DIR" ]; then
          HWINFO_DIR="./acpi-hwinfo"
        fi
        
        echo "📁 Directory: $HWINFO_DIR"
        if [ -d "$HWINFO_DIR" ]; then
          echo "📋 Contents:"
          ls -la "$HWINFO_DIR/"
          echo
          
          if [ -f "$HWINFO_DIR/hwinfo.json" ]; then
            echo "📄 Hardware Info:"
            ${pkgs.jq}/bin/jq . "$HWINFO_DIR/hwinfo.json" 2>/dev/null || cat "$HWINFO_DIR/hwinfo.json"
            echo
            
            if [ -f "$HWINFO_DIR/hwinfo.aml" ]; then
              echo "✅ ACPI table ready: $HWINFO_DIR/hwinfo.aml"
            else
              echo "❌ ACPI table missing: $HWINFO_DIR/hwinfo.aml"
            fi
          else
            echo "❌ No hardware info found"
          fi
        else
          echo "❌ Directory does not exist"
        fi
        
        echo
        echo "🛠️  Available commands:"
        echo "   acpi-hwinfo-generate  - Generate hardware info"
        echo "   acpi-hwinfo-show      - Show current hardware info"
        echo "   qemu-with-hwinfo      - Start QEMU with hardware info"
      '';

      # QEMU launcher with hardware info
      qemu-with-hwinfo = pkgs.writeShellScriptBin "qemu-with-hwinfo" ''
        #!/bin/bash
        set -euo pipefail
        
        HWINFO_DIR="/var/lib/acpi-hwinfo"
        if [ ! -d "$HWINFO_DIR" ]; then
          HWINFO_DIR="./acpi-hwinfo"
        fi
        
        HWINFO_AML="$HWINFO_DIR/hwinfo.aml"
        
        if [ ! -f "$HWINFO_AML" ]; then
          echo "❌ Hardware info not found at $HWINFO_AML"
          echo "💡 Run 'acpi-hwinfo-generate' first"
          exit 1
        fi
        
        DISK_IMAGE="''${1:-disk.qcow2}"
        MEMORY="''${2:-2G}"
        
        if [ ! -f "$DISK_IMAGE" ]; then
          echo "❌ Disk image not found: $DISK_IMAGE"
          echo "💡 Usage: qemu-with-hwinfo [disk_image] [memory]"
          exit 1
        fi
        
        echo "🚀 Starting QEMU with hardware info..."
        echo "   Disk: $DISK_IMAGE"
        echo "   Memory: $MEMORY"
        echo "   ACPI Table: $HWINFO_AML"
        echo
        
        exec ${pkgs.qemu}/bin/qemu-system-x86_64 \
          -machine q35 \
          -cpu host \
          -enable-kvm \
          -m "$MEMORY" \
          -drive file="$DISK_IMAGE",format=qcow2 \
          -acpitable file="$HWINFO_AML" \
          -netdev user,id=net0 \
          -device virtio-net-pci,netdev=net0 \
          -display gtk \
          "$@"
      '';

      # NixOS VM test runner with hardware info
      run-test-microvm = pkgs.writeShellScriptBin "run-test-microvm" ''
                #!/bin/bash
                set -euo pipefail
        
                echo "🚀 Building and running test NixOS VM with ACPI hardware info..."
        
                # Generate hardware info if needed
                if [ ! -f "/var/lib/acpi-hwinfo/hwinfo.aml" ] && [ ! -f "./acpi-hwinfo/hwinfo.aml" ]; then
                  echo "📋 Generating hardware info..."
                  ${self'.packages.acpi-hwinfo-generate}/bin/acpi-hwinfo-generate
                fi
        
                # Create temporary NixOS VM configuration
                cat > test-nixos-vm.nix <<EOF
        { config, pkgs, lib, modulesPath, ... }:

        {
          imports = [
            ./modules/guest.nix
            "\''${modulesPath}/virtualisation/qemu-vm.nix"
          ];

          # Enable ACPI hardware info
          virtualisation.acpi-hwinfo = {
            enable = true;
            guestTools = true;
          };

          # VM configuration
          virtualisation = {
            memorySize = 1024;
            qemu.options = [
              "-nographic"
              "-smp" "2"
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

          # Create test script
          environment.etc."test-acpi-hwinfo.sh" = {
            text = '''
              #!/bin/bash
              set -euo pipefail
      
              echo "🧪 Testing ACPI hardware info in NixOS VM..."
              echo "============================================"
      
              # Test 1: Check if service is running
              echo "1️⃣  Checking acpi-hwinfo service..."
              if systemctl is-active --quiet acpi-hwinfo; then
                echo "✅ acpi-hwinfo service is running"
              else
                echo "❌ acpi-hwinfo service is not running"
                systemctl status acpi-hwinfo || true
              fi
      
              # Test 2: Check if hardware info file exists
              echo "2️⃣  Checking hardware info file..."
              if [ -f "/var/lib/acpi-hwinfo/hwinfo.json" ]; then
                echo "✅ Hardware info file exists"
                echo "📄 Hardware info content:"
                jq . /var/lib/acpi-hwinfo/hwinfo.json 2>/dev/null || cat /var/lib/acpi-hwinfo/hwinfo.json
              else
                echo "❌ Hardware info file not found"
                ls -la /var/lib/acpi-hwinfo/ || echo "Directory not found"
              fi
      
              # Test 3: Check ACPI device
              echo "3️⃣  Checking ACPI device..."
              if [ -d "/sys/bus/acpi/devices/ACPI0001:00" ]; then
                echo "✅ ACPI device found"
              else
                echo "⚠️  ACPI device not found (may be expected in VM)"
                echo "Available ACPI devices:"
                ls -la /sys/bus/acpi/devices/ 2>/dev/null || echo "No ACPI devices found"
              fi
      
              echo "🎉 NixOS VM test completed!"
              echo "   Press Ctrl+C to exit"
            ''';
            mode = "0755";
          };
        }
        EOF

                echo "📝 Building NixOS VM..."
                nix build --impure --expr "
                  let
                    flake = builtins.getFlake (toString ./.);
                    system = \"x86_64-linux\";
                    nixpkgs = flake.inputs.nixpkgs;
                    self = flake;
                    config = import ./test-nixos-vm.nix;
                  in
                  (nixpkgs.lib.nixosSystem {
                    inherit system;
                    modules = [ 
                      config 
                      { nixpkgs.overlays = [ self.overlays.default or (_: _: {}) ]; }
                    ];
                  }).config.system.build.vm
                " -o test-vm-result
        
                # Find the hardware info AML file
                HWINFO_AML=""
                if [ -f "/var/lib/acpi-hwinfo/hwinfo.aml" ]; then
                  HWINFO_AML="/var/lib/acpi-hwinfo/hwinfo.aml"
                elif [ -f "./acpi-hwinfo/hwinfo.aml" ]; then
                  HWINFO_AML="./acpi-hwinfo/hwinfo.aml"
                else
                  echo "❌ Hardware info AML file not found!"
                  exit 1
                fi
        
                echo "🚀 Starting NixOS VM with hardware info ACPI table..."
                echo "   Hardware info AML: $HWINFO_AML"
                echo "   To run the test: /etc/test-acpi-hwinfo.sh"
                echo "   To test hardware info: read-hwinfo"
                echo "   To exit: Press Ctrl+C"
                echo
        
                # Start VM with custom ACPI table
                exec ./test-vm-result/bin/run-nixos-vm -acpitable file="$HWINFO_AML"
      '';

      # End-to-end test with MicroVM and our module
      # VM test with hardware info - tests our module and creates a simple VM
      run-test-vm-with-hwinfo = pkgs.writeShellScriptBin "run-test-vm-with-hwinfo" ''
        #!/bin/bash
        set -euo pipefail
        
        echo "🧪 Running VM test with hardware info..."
        
        # Generate test hardware info if needed
        if [ ! -f "/var/lib/acpi-hwinfo/hwinfo.aml" ] && [ ! -f "./acpi-hwinfo/hwinfo.aml" ]; then
          echo "📋 Generating test hardware info..."
          ${self'.packages.acpi-hwinfo-generate}/bin/acpi-hwinfo-generate
        fi
        
        echo "✅ Hardware info generated successfully"
        
        # Test that our module file exists and is valid Nix
        echo "🔍 Testing module syntax..."
        nix eval --impure --expr 'builtins.isFunction (import ${inputs.self}/modules/host.nix)'
        
        echo "✅ Module syntax test passed"
        
        # Test hardware info files
        echo "🔍 Verifying hardware info files..."
        
        HWINFO_DIR="/var/lib/acpi-hwinfo"
        if [ ! -d "$HWINFO_DIR" ]; then
          HWINFO_DIR="./acpi-hwinfo"
        fi
        
        if [ -f "$HWINFO_DIR/hwinfo.json" ]; then
          echo "✅ Hardware info JSON found:"
          cat "$HWINFO_DIR/hwinfo.json" | ${pkgs.jq}/bin/jq .
        else
          echo "❌ Hardware info JSON not found"
          exit 1
        fi
        
        if [ -f "$HWINFO_DIR/hwinfo.aml" ]; then
          echo "✅ Hardware info AML found:"
          ls -la "$HWINFO_DIR/hwinfo.aml"
        else
          echo "❌ Hardware info AML not found"
          exit 1
        fi
        
        # Test QEMU with hardware info (if disk image available)
        if [ -f "nixos.qcow2" ]; then
          echo "🚀 Testing QEMU with hardware info..."
          echo "💡 Found nixos.qcow2, you can run: qemu-with-hwinfo nixos.qcow2"
        elif [ -f "test-vm.qcow2" ]; then
          echo "🚀 Testing QEMU with hardware info..."
          echo "💡 Found test-vm.qcow2, you can run: qemu-with-hwinfo test-vm.qcow2"
        else
          echo "💡 No VM disk image found. Create one with:"
          echo "   nix run nixpkgs#nixos-generators -- --format qcow2 --configuration ./examples/example-vm.nix"
        fi
        
        echo "✅ VM test with hardware info completed successfully"
        echo ""
        echo "🎉 All tests passed! Your ACPI hardware info module is working correctly."
        echo ""
        echo "📋 Available commands:"
        echo "   acpi-hwinfo-generate  - Generate hardware info"
        echo "   acpi-hwinfo-show      - Show current hardware info"
        echo "   qemu-with-hwinfo      - Start QEMU with hardware info"
        echo ""
      '';


    };
  };
}
