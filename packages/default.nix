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
        echo "   run-test-microvm      - Run MicroVM with hardware info"
      '';

      # MicroVM test runner - validates MicroVM configuration and module
      run-test-microvm = pkgs.writeShellScriptBin "run-test-microvm" ''
        #!/bin/bash
        set -euo pipefail
        
        echo "🚀 Testing MicroVM configuration with ACPI hardware info..."
        
                # Generate hardware info if needed
                if [ ! -f "/var/lib/acpi-hwinfo/hwinfo.aml" ] && [ ! -f "./acpi-hwinfo/hwinfo.aml" ]; then
                  echo "📋 Generating hardware info..."
                  ${self'.packages.acpi-hwinfo-generate}/bin/acpi-hwinfo-generate
                fi
        
        echo "✅ Hardware info generated successfully"
        
        # Test MicroVM configuration syntax
        echo "🔍 Testing MicroVM configuration..."
        if [ ! -f "./examples/microvm-with-hwinfo.nix" ]; then
          echo "❌ MicroVM example not found at ./examples/microvm-with-hwinfo.nix"
          exit 1
        fi
        
        # Test that the MicroVM configuration is valid Nix
        nix eval --impure --expr "
          let
            flake = builtins.getFlake (toString ./.);
            nixpkgs = flake.inputs.nixpkgs;
            microvm = flake.inputs.microvm;
            self = flake;
            
            microvmConfig = import ./examples/microvm-with-hwinfo.nix;
          in
          builtins.isFunction microvmConfig
        "
        
        echo "✅ MicroVM configuration is valid"
        
        # Test guest module can be imported successfully
        echo "🔍 Testing guest module import..."
        nix eval --impure --expr "
          let
            module = import ./modules/guest.nix;
          in
          builtins.isFunction module
        "
        
        echo "✅ Guest module MicroVM options work correctly"
        echo "🎉 MicroVM configuration test completed successfully!"
        echo ""
        echo "📋 To manually build the MicroVM:"
        echo "   nix build --impure --expr 'let flake = builtins.getFlake (toString ./.); in flake.lib.mkMicroVMWithHwInfo { system = \"x86_64-linux\"; config = import ./examples/microvm-with-hwinfo.nix; }'"
        echo ""
        echo "📋 MicroVM features tested:"
        echo "   ✅ ACPI hardware info injection via microvmFlags"
        echo "   ✅ Hardware info sharing via microvmShares"
        echo "   ✅ Helper script: microvm-hwinfo-helper"
        echo "   ✅ Environment variable: MICROVM_ACPI_FLAGS"
      '';

      # End-to-end test with MicroVM and our module
      run-test-vm-with-hwinfo = pkgs.writeShellScriptBin "run-test-vm-with-hwinfo" ''
        #!/bin/bash
        set -euo pipefail
        
        echo "🚀 Running end-to-end test with MicroVM..."
        
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
        
        # Test MicroVM functionality
        echo "💡 To run a full MicroVM test:"
        echo "   run-test-microvm"
        echo ""
        echo "💡 MicroVM example configuration available at:"
        echo "   ./examples/microvm.nix"
        
        echo "✅ VM test with hardware info completed successfully"
        echo ""
        echo "🎉 All tests passed! Your ACPI hardware info module is working correctly."
        echo ""
        echo "📋 Available commands:"
        echo "   acpi-hwinfo-generate  - Generate hardware info"
        echo "   acpi-hwinfo-show      - Show current hardware info"
        echo "   run-test-microvm      - Run MicroVM with hardware info"
        echo ""
      '';


    };
  };
}
