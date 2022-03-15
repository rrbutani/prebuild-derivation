{
  description = "TODO: prebuild-derivation";

  inputs = {
    flake-utils.url = github:numtide/flake-utils;
    nixpkgs.url = github:NixOS/nixpkgs/nixos-21.11;
  };

  # TODO: we have to use `defaultSystems` here instead of `allSystems` to get past eval but we shouldn't
  # need to do this; why is evaluating other systems than the current one not lazy for `nix flake check`?
  outputs = { self, flake-utils, nixpkgs }: with flake-utils.lib; eachSystem defaultSystems (system:
    let
      nixpkgs' = nixpkgs.legacyPackages.${system};

    in rec {
      lib = let
        usingNixpkgsInstance = np:
          (import ./. {
              # The usual default systems + the current system if it's not in the defaults.
              defaultSystems = defaultSystems ++ (if (builtins.any (s: s == system) defaultSystems) then [] else [system]);
              nixpkgs = np;
          }) // {
            inherit usingNixpkgsInstance;
          }
        ;
      in usingNixpkgsInstance nixpkgs';

      checks = with import ./test-utils.nix {
        nixpkgs = nixpkgs';
        inherit (lib) prebuildNixpkg substituteForPrebuilt;
      };
      let
        pkgsToTest = {
          "SingleOutput" = "neofetch";
          "MultiOutput" = "xz";
          "MultiOutputComplex" = "nix";
          "Python" = "python310";
        };

        mapTests = tests: nameF: valF:
          let
            tuples = builtins.map (name: { inherit name; value = tests.${name}; }) (builtins.attrNames tests);
          in
            builtins.listToAttrs (builtins.map (tuple: { name = nameF tuple.name; value = valF tuple.value;}) tuples);
        mapTests' = mapTests pkgsToTest;

        regularChecks = mapTests' (n: "same${n}") check;
        caInputChecks = mapTests' (n: "same${n}CA") checkCA;

        # TODO: check that the pre-built derivation does *not* have a dep on the original package.
        # (until we fix #2 – self-references – we will fail this kind of check).
      in regularChecks // caInputChecks;
  });

  # TODO: tests
  # TODO: examples
  # TODO: CI
}
