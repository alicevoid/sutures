{ ... }:

{
  imports = [
    ./k3s.nix
    ./traefik.nix
    ./argocd.nix
  ];
}
