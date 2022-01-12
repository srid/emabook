{
  description = "emanote";
  inputs = {
    ema.url = "github:srid/ema/master";
    # Use the nixpkgs used by the pinned ema.
    tailwind-haskell.url = "github:srid/tailwind-haskell/master";
    nixpkgs.follows = "ema/nixpkgs";
    tailwind-haskell.inputs.nixpkgs.follows = "ema/nixpkgs";
    tailwind-haskell.inputs.flake-utils.follows = "flake-utils";
    tailwind-haskell.inputs.flake-compat.follows = "flake-compat";
    ema.inputs.flake-utils.follows = "flake-utils";
    ema.inputs.flake-compat.follows = "flake-compat";

    #tagtree = {
    #  url = "github:srid/tagtree";
    #  flake = false;
    #};
    heist = {
      url = "github:srid/heist/emanote";
      flake = false;
    };

    flake-utils.url = "github:numtide/flake-utils";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };
  outputs = inputs@{ self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ]
      (system:
        let
          overlays = [ ];
          pkgs =
            import nixpkgs { inherit system overlays; config.allowBroken = true; };
          # Based on https://github.com/input-output-hk/daedalus/blob/develop/yarn2nix.nix#L58-L71
          filter = name: type:
            let
              baseName = baseNameOf (toString name);
              sansPrefix = pkgs.lib.removePrefix (toString ./.) name;
            in
            # Ignore these files when building emanote source package
              !(
                baseName == "README.md" ||
                sansPrefix == "/bin" ||
                sansPrefix == "/docs" ||
                sansPrefix == "/.github" ||
                sansPrefix == "/.vscode"
              );
          # https://github.com/NixOS/nixpkgs/issues/140774#issuecomment-976899227
          m1MacHsBuildTools =
            pkgs.haskellPackages.override {
              overrides = self: super:
                let
                  workaround140774 = hpkg: with pkgs.haskell.lib;
                    overrideCabal hpkg (drv: {
                      enableSeparateBinOutput = false;
                    });
                in
                {
                  ghcid = workaround140774 super.ghcid;
                  ormolu = workaround140774 super.ormolu;
                };
            };
          project = returnShellEnv:
            pkgs.haskellPackages.developPackage {
              inherit returnShellEnv;
              name = "emanote";
              root = pkgs.lib.cleanSourceWith { inherit filter; src = ./.; name = "emanote"; };
              withHoogle = true;
              overrides = self: super: with pkgs.haskell.lib; {
                ema = disableCabalFlag inputs.ema.defaultPackage.${system} "with-examples";
                tailwind = inputs.tailwind-haskell.defaultPackage.${system};
                # tagtree = self.callCabal2nix "tagtree" inputs.tagtree { };
                # Jailbreak heist to allow newer dlist
                heist = doJailbreak (dontCheck (self.callCabal2nix "heist" inputs.heist { }));
                # lvar = self.callCabal2nix "lvar" inputs.ema.inputs.lvar { }; # Until lvar gets into nixpkgs
              };
              modifier = drv:
                pkgs.haskell.lib.addBuildTools drv
                  (with (if system == "aarch64-darwin"
                  then m1MacHsBuildTools
                  else pkgs.haskellPackages); [
                    # Specify your build/dev dependencies here. 
                    cabal-fmt
                    cabal-install
                    ghcid
                    haskell-language-server
                    ormolu
                    pkgs.nixpkgs-fmt

                    inputs.tailwind-haskell.defaultPackage.${system}
                  ]);
            };
        in
        {
          # Used by `nix build` & `nix run`
          defaultPackage = project false;

          # Used by `nix develop`
          devShell = project true;
        }) //
    {
      homeManagerModule = import ./home-manager-module.nix;
    };
}
