{ pkgs, ... }:

# pharika — server host specifics only.
# Shared config comes from modules/common.nix + modules/server.nix (wired in flake.nix).
{
  imports = [ ./hardware-configuration.nix ];

  # host
  networking.hostName = "pharika";

  # Optional static ethernet (leave commented unless needed)
  # networking.networkmanager.unmanaged = [ "eno2" ];
  # networking.interfaces.eno2.ipv4.addresses = [{
  #   address = "10.0.0.3";
  #   prefixLength = 24;
  # }];
  # networking.defaultGateway = {
  #   address = "10.0.0.1";
  #   interface = "eno2";
  # };
  # networking.nameservers = [ "1.1.1.1" "9.9.9.9" ];

  # user (server extras on top of the base alice from common.nix)
  # TODO: add hosts/pharika/keys/athreos.pub and re-enable this. SSH is
  # key-only (PasswordAuthentication = false), so without a key you cannot
  # log in remotely — add the key before relying on remote access.
  # users.users.alice.openssh.authorizedKeys.keyFiles = [ ./keys/athreos.pub ];

  # host-specific packages
  environment.systemPackages = with pkgs; [
    git
    curl
    pciutils
    usbutils
    k3s
  ];

  # never change
  system.stateVersion = "26.05";
}
