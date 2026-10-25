{ ... }:

# Every k3s node (server and agent): host settings that Cilium needs on each machine.
#   Imported by default.nix (server, pharika) and agent.nix (agents, ephara).

{
  # Firewall (disabled in server.nix; this applies if it is turned on)
  networking.firewall = {
    # Trust the Cilium interfaces so pods can reach the API server and CoreDNS.
    trustedInterfaces = [
      "cilium_host"
      "cilium_net"
      "cilium_vxlan"
      "lxc+"
    ];
  };

  systemd.services.tailscale-src-valid-mark = {
    after = [ "tailscaled.service" ];
    partOf = [ "tailscaled.service" ];
    wantedBy = [ "tailscaled.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for _ in $(seq 1 60); do
        [ "$(cat /proc/sys/net/ipv4/conf/all/src_valid_mark)" = 1 ] && break
        sleep 1
      done
      echo 0 > /proc/sys/net/ipv4/conf/all/src_valid_mark
    '';
  };
}
