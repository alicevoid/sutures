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
      pkgs = nixpkgs.legacyPackages.${system};

      # Home-manager wiring, shared by every host (full home everywhere).
      homeManager = {
        home-manager.useGlobalPkgs = true; # uses system nixpkgs, no duplicate downloads
        home-manager.useUserPackages = true; # installs HM packages into user profile
        home-manager.users.alice = {
          imports = [
            nixvim.homeModules.nixvim
            ./home/alice.nix
          ];
        };
        home-manager.extraSpecialArgs = { inherit inputs; };
      };

      # mkSystem no longer bakes in any class/desktop assumptions. Each host
      # declares its class module (laptop.nix / server.nix), any profiles, and
      # its own host config via `modules`.
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
          ./hosts/pharika/configuration.nix
          ./hosts/pharika/hardware-configuration.nix
        ];
      };

      # Ephemeral, user-space profiles — enter with `nix develop .#<name>`,
      # everything disappears when you exit the shell. See PROFILES.md.
      devShells.${system} = {
        dev = pkgs.mkShell {
          packages = with pkgs; [
            python3
            gh
            git-extras
          ];
        };
      };
    };
}
