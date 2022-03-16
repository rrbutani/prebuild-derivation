{
  description = "TODO: example of prebuild-derivation being used";

  # inputs = {
  #   flake-utils.url = github:numtide/flake-utils;
  #   nixpkgs.url = github:NixOS/nixpkgs/nixos-21.11;
  # } // (if (import ./sources.nix).usePrebuilts then {} else {
  #   lorri = {
  #     url = github:nix-community/lorri;
  #     flake = false;
  #   }; # TODO!!!
  # });

  inputs = {
    flake-utils.url = github:numtide/flake-utils;
    nixpkgs.url = github:NixOS/nixpkgs/nixos-21.11;
    pbd.url = path:../; # See: https://github.com/NixOS/nix/issues/3978
  };

  outputs = { self, flake-utils, nixpkgs, pbd }: with flake-utils.lib; eachSystem defaultSystems (system:
    let
      nixpkgs' = nixpkgs.legacyPackages.${system};
      pbd' = pbd.lib.${system};

      pkg = "fortune";

      sources = import ./sources.nix;
      pkgDerivation = pbd'.conditionallySubstitute {
        nixpkgs = nixpkgs';
        cond = sources.usePrebuilts;
        original = nixpkgs'.${pkg};
        prebuilts = sources.${pkg};
        makeOriginalContentAddressable = true;
      };

      # Don't expose this package if we're already a flake containing prebuilts.
      packages = if sources.usePrebuilts
        then {}
        else {
          withPrebuilts = let
            prebuilt = pbd'.prebuildNixpkg { inherit pkg; };
          in
            pbd'.createTarballWithPrebuiltSets {
              nixpkgs = nixpkgs';
              base = ./.;
              prebuiltSets = { "${pkg}" = prebuilt; };
          };
      };

    in {
      # TODO: do a heavier check
      checks = {
        "run-${pkg}" = derivation {
          name = "${pkg}-check";
          builder = with nixpkgs'; "${bash}/bin/bash";
          args = [(nixpkgs'.writeScript "check-${pkg}.sh" ''
            ${pkgDerivation}/bin/${pkg} && ${nixpkgs'.coreutils}/bin/touch $out
          '')];
          inherit system;
        };
      };
      defaultApp = { type = "app"; program = "${pkgDerivation}/bin/${pkg}"; };
      defaultPackage = pkgDerivation;

      inherit packages;
    }
  );
}
