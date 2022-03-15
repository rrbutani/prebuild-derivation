{
  description = "TODO: prebuild-derivation";

  inputs = {
    flake-utils.url = github:numtide/flake-utils;
    nixpkgs.url = github:NixOS/nixpkgs/nixos-21.11;
  };

  outputs = { self, flake-utils, nixpkgs }: with flake-utils.lib; eachSystem allSystems (system:
    let
      nixpkgs' = nixpkgs.legacyPackages.${system};

    in {
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

      checks = with import ./test-utils.nix { };
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
            builtins.listToAttrs (builtins.map (tuple: { name = nameF tuple.name; value = valF tuple.value;}));
        mapTests' = mapTests pkgsToTest;

        regularChecks = mapTests' (n: "same${n}") check;
        caInputChecks = mapTests' (n: "same${n}CA") checkCA;
      in regularChecks // caInputChecks;
  });

  # TODO: tests
  # TODO: examples
  # TODO: CI
}
