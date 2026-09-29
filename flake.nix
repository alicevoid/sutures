{
  description = "sutures - athreos, kunoros & pharika";

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
      system = "x86_64-linux";

      homeManager = {
        home-manager.useGlobalPkgs = true; 
        home-manager.useUserPackages = true;
        home-manager.users.alice = {
          imports = [
            nixvim.homeModules.nixvim
            ./home/alice.nix
          ];
        };
        home-manager.extraSpecialArgs = { inherit inputs; };
      };

      mkSystem =
        modules:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/common.nix
            home-manager.nixosModules.home-manager
            homeManager
          ]
          ++ modules;
        };

    in
    {
      nixosConfigurations = {
        kunorOS = mkSystem [
          ./modules/laptop.nix
          ./profiles/gaming.nix
          ./hosts/kunoros/configuration.nix
          ./hosts/kunoros/hardware-configuration.nix
        ];

        athreOS = mkSystem [
          ./modules/laptop.nix
          ./profiles/gaming.nix
          ./hosts/athreos/configuration.nix
          ./hosts/athreos/hardware-configuration.nix
        ];

        pharika = mkSystem [
          ./modules/server.nix
          ./modules/k8s 
          ./hosts/pharika/configuration.nix
          ./hosts/pharika/hardware-configuration.nix
        ];
      };
    };
}
