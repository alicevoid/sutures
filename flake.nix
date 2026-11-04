{
  description = "sutures - athreos, kunoros, pharika & ephara";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim.url = "github:nix-community/nixvim/nixos-26.05";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nixvim,
      sops-nix,
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
          sops-nix.nixosModules.sops
          ./modules/secrets.nix
          ./modules/mail.nix
          ./modules/k8s 
          ./hosts/pharika/configuration.nix
          ./hosts/pharika/hardware-configuration.nix
        ];

        ephara = mkSystem [
          ./modules/server.nix
          sops-nix.nixosModules.sops
          ./modules/secrets.nix
          ./modules/mail.nix
          ./modules/k8s/agent.nix
          ./hosts/ephara/configuration.nix
          ./hosts/ephara/hardware-configuration.nix
        ];
      };
    };
}
