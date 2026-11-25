{ ... }:

# Host settings that Cilium needs on every k3s node, server and agent.

{
  # Pods reach the host through the trusted Cilium interfaces. The nftables wildcard is "*"
  #   ("lxc+" is iptables syntax and matches nothing). Envoy's replies are NOTRACK, so pod packets
  #   to the Gateway look "invalid" to conntrack and must be accepted by interface first.
  #   Cluster ports accept only the nodes and the pod CIDR: VXLAN, Cilium health, Hubble,
  #   node-exporter, Cilium and Envoy metrics, kubelet.
  networking.firewall = {
    trustedInterfaces = [
      "cilium_host"
      "cilium_net"
      "cilium_vxlan"
      "lxc*"
    ];
    # Cilium marks Gateway traffic 0x200 for Envoy, and that mark routes to a table with only a
    #   local route, so the reverse-path check drops it.
    extraReversePathFilterRules = ''
      meta mark & 0x00000f00 == 0x00000200 accept
    '';
    extraInputRules = ''
      ip saddr { 10.0.0.141, 10.0.0.65, 10.42.0.0/16 } udp dport 8472 accept
      ip saddr { 10.0.0.141, 10.0.0.65, 10.42.0.0/16 } tcp dport { 4240, 4244, 9100, 9962-9965, 10250 } accept
    '';
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
