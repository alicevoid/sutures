{ ... }:

{
  imports = [
    ./k3s.nix
    ./cilium.nix
    ./argocd.nix
  ];
}
