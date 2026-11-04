{ ... }:

# Host settings that Cilium needs on every k3s node, server and agent.

{
  # The firewall is off (server.nix). If it is turned on, pods still reach the API server and CoreDNS.
  networking.firewall = {
    trustedInterfaces = [
      "cilium_host"
      "cilium_net"
      "cilium_vxlan"
      "lxc+"
    ];
  };

  # Tailscale sets src_valid_mark=1, and the kernel then drops Envoy's backend replies as
  #   martians (every routed request times out). Reset it after each tailscaled start.
  #   Remove when tailscale/tailscale#19796 is fixed.
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
