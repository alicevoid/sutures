{ ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # host
  networking.hostName = "pharika";

  # Static Ethernet Stuff (not needed? lol)
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

  # SSH keyFiles
  users.users.alice.openssh.authorizedKeys.keyFiles = [ ./keys/athreos.pub ];

  # never change
  system.stateVersion = "26.05";
}
