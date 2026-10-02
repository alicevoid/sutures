{ ... }:

{
  imports = [
    ./k3s.nix
    ./traefik.nix
    ./authelia.nix
    ./observability.nix
    ./memos.nix
    ./karakeep.nix
  ];
}
