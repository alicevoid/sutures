{
  description = "sutures - kunoros & athreos";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = { self, nixpkgs }: {
    nixosConfigurations = {

      kunoros = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./modules/common.nix
          ./hosts/kunoros/configuration.nix
          ./hosts/kunoros/hardware-configuration.nix
        ];
      };

      athreos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./modules/common.nix
          ./hosts/athreos/configuration.nix
          ./hosts/athreos/hardware-configuration.nix
        ];
      };

    };
  };
}
