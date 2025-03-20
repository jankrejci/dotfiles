{ pkgs, ... }:

pkgs.writeShellApplication {
  name = "wireguard-config";
  runtimeInputs = with pkgs; [
    wireguard-tools
    qrencode
  ];
  text = ''
    if [ $# -ne 1 ]; then
      echo "Usage: wireguard HOSTNAME"
      exit 1
    fi
  
    HOSTNAME=$1

    SERVER_HOSTNAME="vpsfree"
    DOMAIN="vpn"

    # Get IP address and server key using nix eval
    IP_ADDRESS=$(nix eval --raw ".#nixosConfigurations.$HOSTNAME.config.hosts.self.ipAddress")
    SERVER_PUBKEY=$(nix eval --raw ".#nixosConfigurations.$HOSTNAME.config.hosts.$SERVER_HOSTNAME.wgPublicKey")
  
    echo "Generating WireGuard configuration for $HOSTNAME with IP $IP_ADDRESS"
  
    # Generate new keys
    PRIVATE_KEY=$(wg genkey)
    PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)
  
    # Check if host directory exists
    if [ ! -d "hosts/$HOSTNAME" ]; then
      echo "Directory hosts/$HOSTNAME does not exist"
      exit 1
    fi  

    # Write public key to file
    echo "$PUBLIC_KEY" >"hosts/$HOSTNAME/wg-key.pub"
    echo "Public key written to hosts/$HOSTNAME/wg-key.pub"
  
    # Create config file
    CONFIG_DIR=$(mktemp -d)
    CONFIG_FILE="$CONFIG_DIR/wg0.conf"
  
    cat > $CONFIG_FILE << EOF
    [Interface]
    PrivateKey = $PRIVATE_KEY
    Address = $IP_ADDRESS
    DNS = 192.168.99.1, $DOMAIN
  
    [Peer]
    PublicKey = $SERVER_PUBKEY
    AllowedIPs = 192.168.99.0/24
    Endpoint = 37.205.13.227:51820
    EOF
  
    # Generate QR code
    qrencode -o "$CONFIG_DIR/wg0.png" < "$CONFIG_FILE"
  
    echo "Configuration generated at: $CONFIG_FILE"
    echo "QR code generated at: $CONFIG_DIR/wg0.png"
  '';
}
