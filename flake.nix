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

        e2e = let
          # exampleFlake = builtins.getFlake (toString ./example);
          exampleFlake = (import ./example/flake.nix).outputs { self = exampleFlake; inherit flake-utils nixpkgs; pbd = self; };
          flakeWithPrebuilts = exampleFlake.packages.${system}.withPrebuilts;
          # flakeWithPrebuilts' = builtins.getFlake (toString flakeWithPrebuilts);

          # This is IFD and, because `nix flake check` evaluates all systems, thus breaks if your
          # system cannot build for *all* the defaultSystems.
          #
          # So, we wrap it in a tryEval. edit: nvm, this doesn't help...
          #
          # Gonna have to resort to hardcoding a system (yuck). TODO: find a workaround?
          # flakeWithPrebuilts' = builtins.tryEval (
          #   (import flakeWithPrebuilts).outputs { self = flakeWithPrebuilts'; inherit flake-utils nixpkgs; pbd = self; }
          # );
          #
          # Okay: the workaround is that this test only runs with `--impure` (even though it is actually perfectly
          # pure).
          flakeWithPrebuiltsTarball = "${flakeWithPrebuilts}";
          flakeWithPrebuiltsExtracted = derivation {
            name = "extract-flake-tarball";
            inherit system;
            builder = "${nixpkgs'.bash}/bin/bash";
            args = [(nixpkgs'.writeScript "extract.sh" ''
              export PATH="${nixpkgs'.xz}/bin"
              ${nixpkgs'.coreutils}/bin/mkdir -p $out
              ${nixpkgs'.gnutar}/bin/tar xvf "${flakeWithPrebuiltsTarball}/archive.tar.xz" -C $out
            '')];
          };

          flakeWithPrebuilts' =
            (import "${flakeWithPrebuiltsExtracted}/tarball-with-prebuilts/flake.nix").outputs { self = flakeWithPrebuilts'; inherit flake-utils nixpkgs; pbd = self; }
          ;

          dbg = x: builtins.trace x x;
        in
          if builtins ? currentSystem && system == builtins.currentSystem
          then
            dbg flakeWithPrebuilts'.checks.${system}
          else
            {};

        # TODO: check that the pre-built derivation does *not* have a dep on the original package.
        # (until we fix #2 – self-references – we will fail this kind of check).
      in regularChecks // caInputChecks // e2e;
  });

  # TODO: tests
  # TODO: examples
  # TODO: CI (`nix flake check`, `nix flake check --impure`)
}
