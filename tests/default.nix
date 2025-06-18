# Test configurations for ACPI hardware info
{ inputs, ... }:
{
  perSystem = { config, self', inputs', pkgs, system, ... }: {
    packages = {


      # Test runner script
      test-runner = pkgs.writeShellScriptBin "test-acpi-hwinfo" ''
        set -euo pipefail
        
        echo "🧪 ACPI Hardware Info Test Runner"
        echo "================================="
        
        # Ensure we have test hardware info
        if [ ! -f "/var/lib/acpi-hwinfo/hwinfo.aml" ]; then
          echo "📝 Creating test hardware info..."
          ${self'.packages.create-test-hwinfo}/bin/create-test-hwinfo \
            "TEST_NVME_SERIAL_123" \
            "00:11:22:33:44:55" \
            "/var/lib/acpi-hwinfo"
        fi
        
        echo "✅ Hardware info ready"
        echo "📋 Hardware info contents:"
        cat /var/lib/acpi-hwinfo/hwinfo.json
        echo
        
        echo "🎉 Basic test completed successfully!"
        echo "   For VM testing, use the vm-image tests:"
        echo "   nix run .#run-test-vm"
        echo "   nix run .#run-test-vm-with-hwinfo"
      '';

      # Integration test that verifies end-to-end functionality
      integration-test = pkgs.writeShellScriptBin "integration-test" ''
        set -euo pipefail
        
        echo "🔬 ACPI Hardware Info Integration Test"
        echo "====================================="
        
        # Create temporary directory for test
        TEST_DIR=$(mktemp -d)
        trap "rm -rf $TEST_DIR" EXIT
        
        echo "📁 Test directory: $TEST_DIR"
        
        # Step 1: Generate test hardware info
        echo "1️⃣  Generating test hardware info..."
        ${self'.packages.create-test-hwinfo}/bin/create-test-hwinfo \
          "INTEGRATION_TEST_SERIAL" \
          "aa:bb:cc:dd:ee:ff" \
          "$TEST_DIR"
        
        # Verify files were created
        if [ -f "$TEST_DIR/hwinfo.aml" ] && [ -f "$TEST_DIR/hwinfo.json" ]; then
          echo "✅ Hardware info files created"
        else
          echo "❌ Failed to create hardware info files"
          exit 1
        fi
        
        # Step 2: Verify JSON content
        echo "2️⃣  Verifying hardware info content..."
        NVME_SERIAL=$(jq -r '.nvme_serial' "$TEST_DIR/hwinfo.json")
        MAC_ADDRESS=$(jq -r '.mac_address' "$TEST_DIR/hwinfo.json")
        
        if [ "$NVME_SERIAL" = "INTEGRATION_TEST_SERIAL" ] && [ "$MAC_ADDRESS" = "aa:bb:cc:dd:ee:ff" ]; then
          echo "✅ Hardware info content verified"
        else
          echo "❌ Hardware info content mismatch"
          echo "   Expected: INTEGRATION_TEST_SERIAL, aa:bb:cc:dd:ee:ff"
          echo "   Got: $NVME_SERIAL, $MAC_ADDRESS"
          exit 1
        fi
        
        # Step 3: Test ACPI table compilation
        echo "3️⃣  Testing ACPI table..."
        if [ -s "$TEST_DIR/hwinfo.aml" ]; then
          echo "✅ ACPI table compiled successfully"
        else
          echo "❌ ACPI table is empty or missing"
          exit 1
        fi
        
        # Step 4: Test package builds
        echo "4️⃣  Testing package builds..."
        nix --extra-experimental-features "nix-command flakes" build --no-link .#acpi-hwinfo-generate .#acpi-hwinfo-show .#hwinfo-status .#qemu-with-hwinfo
        echo "✅ All packages build successfully"
        
        echo "🎉 Integration test passed!"
        echo "   All components working correctly"
      '';
    };
  };
}
