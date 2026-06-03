{
  description = "sutures - kunoros & athreos";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim.url = "github:nix-community/nixvim/nixos-26.05";

  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nixvim,
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
              home-manager.users.alice = {
                imports = [
                  nixvim.homeModules.nixvim
                  ./home/alice.nix
                ];
              };
              home-manager.extraSpecialArgs = { inherit inputs; };
            }
          ]
          ++ modules;
        };

    in
    {
      nixosConfigurations = {
        kunorOS = mkSystem "x86_64-linux" [
          ./hosts/kunoros/configuration.nix
          ./hosts/kunoros/hardware-configuration.nix
        ];

        athreOS = mkSystem "x86_64-linux" [
          ./hosts/athreos/configuration.nix
          ./hosts/athreos/hardware-configuration.nix
        ];
      };
    };
}
