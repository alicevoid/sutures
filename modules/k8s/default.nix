{ ... }:

{
  imports = [
    ./node.nix
    ./k3s.nix
    ./cilium.nix
    ./argocd.nix
  ];
}
