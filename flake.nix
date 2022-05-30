{
  description = "emanote";
  nixConfig = {
    extra-substituters = "https://cache.garnix.io";
    extra-trusted-public-keys = "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=";
  };
  inputs = {
    ema.url = "github:srid/ema/multisite";
    nixpkgs.follows = "ema/nixpkgs";
    tailwind-haskell.url = "github:srid/tailwind-haskell/master";
    tailwind-haskell.inputs.ema.follows = "ema";
    flake-compat.url = "github:edolstra/flake-compat";
    flake-compat.flake = false;
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs.follows = "nixpkgs";
    haskell-flake.url = "github:srid/haskell-flake/overrides";

    pandoc-link-context.url = "github:srid/pandoc-link-context/master";
    pandoc-link-context.flake = false;

    # 0.5.1.0 is broken on nixpkgs
    ixset-typed.url = "github:well-typed/ixset-typed";
    ixset-typed.flake = false;

    heist = {
      url = "github:srid/heist/emanote";
      flake = false;
    };
  };
  outputs = inputs@{ self, nixpkgs, flake-parts, haskell-flake, ... }:
    flake-parts.lib.mkFlake { inherit self; } {
      systems = nixpkgs.lib.systems.flakeExposed;
      imports = [
        haskell-flake.flakeModule
      ];
      perSystem = { self', system, inputs', pkgs, ... }: {
        haskellProjects.emanote = {
          buildTools = hp: {
            inherit (pkgs)
              treefmt
              nixpkgs-fmt;
            inherit (hp)
              cabal-fmt
              ormolu;
            tailwind-haskell = inputs'.tailwind-haskell.defaultPackage;
          };
          overrides = self: super: with pkgs.haskell.lib; {
            ema = inputs'.ema.packages.default;
            tailwind = inputs.tailwind-haskell.defaultPackage.${system};
            # Jailbreak heist to allow newer dlist
            heist-emanote = doJailbreak (dontCheck (self.callCabal2nix "heist-emanote" inputs.heist { }));
            ixset-typed = doJailbreak (dontCheck (self.callCabal2nix "ixset-typed" inputs.ixset-typed { }));
            pandoc-link-context = self.callCabal2nix "pandoc-link-context" inputs.pandoc-link-context { };
          };
        };
      };
    };

}
