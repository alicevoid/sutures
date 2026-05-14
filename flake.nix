{
  description = "sutures - kunoros & athreos";

  inputs = {
	nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

        nix4nvchad = {
          url = "github:nix-community/nix4nvchad";
          inputs.nixpkgs.follows = "nixpkgs";
        };

      };

  outputs = { self, nixpkgs, nix4nvchad }@inputs: {
    nixosConfigurations = {

      kunoros = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./modules/common.nix
          ./hosts/kunoros/configuration.nix
          ./hosts/kunoros/hardware-configuration.nix
        ];
      };

      athreos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./modules/common.nix
          ./hosts/athreos/configuration.nix
          ./hosts/athreos/hardware-configuration.nix
        ];
      };

    };
  };
}
