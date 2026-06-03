{
  description = "sutures - kunoros & athreos";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
    }@inputs:
    let
      mkSystem =
        system: modules:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/common.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true; # uses system nixpkgs, no duplicate downloads
              home-manager.useUserPackages = true; # installs HM packages into user profile
              home-manager.users.alice = import ./home/alice.nix;
              home-manager.extraSpecialArgs = { inherit inputs; };
            }
          ]
          ++ modules;
        };

    in
    {
      nixosConfigurations = {
        kunoros = mkSystem "x86_64-linux" [
          ./hosts/kunoros/configuration.nix
          ./hosts/kunoros/hardware-configuration.nix
        ];

        athreos = mkSystem "x86_64-linux" [
          ./hosts/athreos/configuration.nix
          ./hosts/athreos/hardware-configuration.nix
        ];
      };
    };
}
