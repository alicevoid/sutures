{ ... }:

{
  imports = [
    ./k3s.nix
    ./observability.nix
    ./memos.nix
    ./karakeep.nix
  ];
}
