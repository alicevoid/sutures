{ ... }:

{
  imports = [
    ./k3s.nix
    ./traefik.nix
    ./observability.nix
    ./memos.nix
    ./karakeep.nix
  ];
}
