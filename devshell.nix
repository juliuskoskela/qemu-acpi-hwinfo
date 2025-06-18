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
    echo "  nix run .#test-microvm-with-hwinfo  - Run comprehensive MicroVM test"
    echo "  nix run .#generate-hwinfo           - Generate hardware info ACPI table"
    echo "  nix run .#read-hwinfo               - Read hardware info from ACPI"
    echo ""
    echo "Development tools available:"
    echo "  iasl, nvme, qemu-system-x86_64"
    echo ""
    echo "Quick start:"
    echo "  nix run .#test-microvm-with-hwinfo"
  '';
}