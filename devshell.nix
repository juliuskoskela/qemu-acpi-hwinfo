{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    acpica-tools
    jq
    qemu
    git
  ];
  
  shellHook = ''
    echo "🔧 MicroVM Hardware Info Development Environment"
    echo ""
    echo "Available commands:"
    echo "  nix run .#microvm-run             - Run MicroVM directly"
    echo "  nix run .#acpi-hwinfo-generate    - Generate hardware info"
    echo "  nix run .#run-test-vm-with-hwinfo - Run end-to-end test"
    echo ""
    echo "🧪 To test the full workflow:"
    echo "  1. run-test-vm-with-hwinfo  # Generate hardware info and test"
    echo "  2. nix run .#microvm-run    # Start the MicroVM"
    echo "  3. In VM: /etc/test-hwinfo.sh  # Test hardware info access"
    echo ""
  '';
}