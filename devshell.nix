{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  name = "qemu-acpi-hwinfo-dev";
  
  buildInputs = with pkgs; [
    # Core tools
    nvme-cli
    acpica-tools
    qemu
    
    # For VM testing
    microvm
    
    # Development tools
    git
    vim
    htop
    curl
    
    # Network tools
    iproute2
    netcat
    
    # Debugging tools
    binutils
    hexdump
    file
  ];
  
  shellHook = ''
    echo "🚀 QEMU ACPI Hardware Info Development Environment"
    echo "Available commands:"
    echo "  run-test-vm-with-hwinfo  - Run end-to-end test with MicroVM"
    echo "  test-build               - Test building hardware info"
    echo "  test-guest-read          - Test guest reading functionality"
    echo ""
    echo "Development tools available:"
    echo "  iasl, nvme, qemu-system-x86_64, microvm"
    echo ""
  '';
}