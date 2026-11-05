{
  description = "NixOS HTPC (tv) - replacement for the CachyOS HTPC VM on tower";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    helium = {
      url = "github:oxcl/nix-flake-helium-browser";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, helium, ... }:
    let
      system = "x86_64-linux";
      mkHost = extraModules: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit helium; };
        modules = [
          ./configuration.nix
        ] ++ extraModules;
      };
    in
    {
      nixosConfigurations.nixos-tv = mkHost [ ./modules/vm-disk.nix ];

      # Raw EFI disk image for the Unraid libvirt domain (build once, then use nixos-rebuild).
      packages.${system}.image =
        (mkHost [ ./modules/vm-disk.nix "${nixpkgs}/nixos/modules/virtualisation/disk-image.nix" {
          image.format = "raw";
          image.efiSupport = true;
          virtualisation.diskSize = "auto";
        } ]).config.system.build.image;
    };
}
