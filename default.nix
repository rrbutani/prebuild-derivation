{
  # We'd rather get this from `flake-utils` but we don't want that to be a
  # requirement for using this (in non-flake form) so we hardcode the current
  # default list here:
  defaultSystems ? [
    "aarch64-linux"
    "aarch64-darwin"
    "i686-linux"
    "x86_64-linux"
    "x86_64-darwin"
  ]
  # Default `nixpkgs` instance to use, if not specified.
, nixpkgs ? null
}:

let
  nixpkgsDefault = if nixpkgs != null
    then nixpkgs
    else builtins.throw "Please provide a `nixpkgs` instance!";

  prebuild = import ./prebuild.nix;
  restore = import ./restore.nix;

  # Takes a nixpkgs instance, a name of a package or a function that gets the
  # package from a nixpkgs instance.
  prebuildNixpkg =
  { nixpkgs ? nixpkgsDefault
    # The package to build.
    #
    # Either:
    #   - a string matching the name of the attribute in `nixpkgs` containing
    #     the package's derivation
    #     + i.e. `"neofetch"`
    #   - or, a function that takes the nixpkgs instance and produces the
    #     derivation of the package to prebuild
    #     + i.e. `n: n.python3Packages.zstd`
  , pkg
  , outputsToPackage ? null
  }:
    let
      # If `pkg` isn't a function, turn it into a function that looks up the
      # `pkg` field:
      pkg' = if builtins.isString pkg then builtins.getAttr pkg else pkg;
    in
    prebuildDerivation { inherit nixpkgs outputsToPackage; target = (pkg' nixpkgs); };

  # TODO: test!

  # Build a nixpkgs package for multiple systems, using cross-compilation.
  prebuildNixpkgForSystems =
  { nixpkgs ? nixpkgsDefault
    # The package to build.
    #
    # Either:
    #   - a string matching the name of the attribute in `nixpkgs` containing
    #     the package's derivation
    #     + i.e. `"neofetch"`
    #   - or, a function that takes the nixpkgs instance and produces the
    #     derivation of the package to prebuild
    #     + i.e. `n: n.python3Packages.zstd`
  , pkg
    # The systems to build the package for.
  , systemNames ? defaultSystems
  }:
    let
      # If `pkg` isn't a function, turn it into a function that looks up the
      # `pkg` field:
      pkg' = if builtins.isString pkg then builtins.getAttr pkg else pkg;
    in
    prebuildDerivations {
      inherit nixpkgs;
      derivations = (builtins.map (sys: pkg' nixpkgs.pkgsCross.${sys}) systemNames);
    };

  # Takes a derivation.
  #
  # Produces a dict:
  # ```
  # { system-name = «derivation»; }
  # ```
  #
  # The produces derivation builds a tarball and some metadata; the tarball
  # contains the derivation's outputs and the metadata file contains information
  # about the build time and runtime dependencies:
  #  - metadata.json (details about the original derivation)
  #  - archive.tar.xz; a tarball with the outputs as directories; i.e.:
  #    ```
  #    |- out
  #    |- lib
  #    |- bin
  #    |- doc
  #    |- ...
  #    ```
  #
  # We produce one tarball + metadata file per system (instead of just one
  # tarball with artifacts for all the systems) because this makes it easier to
  # support multiple systems. Instead of requiring you to have one machine that
  # supports building for all the architectures, you can build the tarballs on
  # separate machines and then use `mergePrebuilts`.
  prebuildDerivation =
  { nixpkgs ? nixpkgsDefault
    # The derivation to produce the prebuilt for.
  , target
    # The outputs from the derivation to add to the prebuilt's tarball.
    #
    # By default (`null`), all outputs will be added.
  , outputsToPackage ? null
  }:
  let
    isDerivation = target ? type && target.type == "derivation";
    sys = if isDerivation
      then target.system
      else builtins.throw "the `target` to make a prebuilt for must be a derivation!";
  in {
    "${sys}" = prebuild { np = nixpkgs; inherit outputsToPackage target; };
  };

  # Merges prebuilts (i.e. the output of `preBuild...`) into a single dict.
  #
  # Errors if there's more than one prebuilt for a particular system.
  mergePrebuilts = prebuilts:
    let
      func = existing: next:
        let
          duplicates = builtins.attrNames (builtins.intersectAttrs existing next);
          check = (builtins.length duplicates != 0) &&
            (builtins.throw
              "Got multiple prebuilts for these systems: " +
              (builtins.toString duplicates)
            );
        in
          existing // next;
    in builtins.foldl' func {} prebuilts;


  # Convenience function that builds a bunch of prebuilts using `preBuildDerivation` and
  # merges them using `mergePrebuilts`.
  prebuildDerivations = { nixpkgs, derivations }:
    mergePrebuilts (map (target: prebuildDerivation { inherit nixpkgs target; }) derivations);


  # TODO: strict/lenient mode on the "replace" step (i.e. warn on different
  # inputs for the runtime version or error)

  # TODO: call a diff tool (not nix-diff, unfortunately – if there's mismatch we
  # literally don't have the derivation we're expecting available to diff
  # against).

  # TODO: Have the substitute derivation steal test/check phases? (or just
  # override the fetch/configure/build phases, etc.)

  # Takes a derivation and a set of prebuilts.
  #
  # Gives back a new derivation that can be used in lieu of the original but
  # uses the prebuilt artifacts.
  substituteForPrebuilt =
  { nixpkgs ? nixpkgsDefault
  , original
  , prebuilts
  , errorOnMismatch ? { runtimeDeps = true; buildDeps = false; extraAttrs = false; }
  , produceContentAddressedDerivations ? true
  }:
  let
    isDerivation = x: x ? type && x.type == "derivation";
    originalSys = if isDerivation original
      then original.system
      else builtins.throw
        "The derivation to replace (`original`) must actually be a derivation!";

    nixpkgsSysMatchesOriginalSys = if nixpkgs.system == originalSys
      then true
      else builtins.throw
        ''
        The derivation to replace is for system `${originalSys}` but the
        provided nixpkgs instance is for system `${nixpkgs.system}`.

        Because the substitue derivation that's produced uses packages from
        nixpkgs like `bash` and `xz`, you must provide a nixpkgs instance for
        the same system as the derivation you are trying to substitute.
        '';
    prebuilt = if nixpkgsSysMatchesOriginalSys && builtins.hasAttr originalSys prebuilts
      then prebuilts.${originalSys}
      else builtins.throw
        ''
        There does not appear to be a prebuilt for the system `${originalSys}` in
        the supplied prebuilts for `${original.name}`.

        However, we do have prebuilts for: `${toString (builtins.attrNames prebuilts)}`.
        '';

    # We're looking for a path...
    prebuilt' = if isDerivation prebuilt
      then prebuilt.outPath
      else prebuilt;
  in
    restore {
      dir = prebuilt';
      np = nixpkgs;
      sourceDerivation = original;
      checkRuntimeDeps = errorOnMismatch.runtimeDeps;
      checkBuildDeps = errorOnMismatch.buildDeps;
      checkExtraAttrs = errorOnMismatch.extraAttrs;
      useContentAddressedDerivations = produceContentAddressedDerivations;
    }
  ;

  # Convenience function.
  #
  # Optionally turns the `original` derivation into a content addressable derivation so that the
  # prebuilt that's generated will have the same nix store path as the original.
  conditionallySubstitute = args@
  { nixpkgs ? nixpkgsDefault
    # The original derivation.
  , original
    # Should we substitute?
  , cond
    # Prebuilts to potentially use to substitute `original`.
  , prebuilts
  , makeOriginalContentAddressable ? false
  , ... # errorOnMismatch, produceContentAddressedDerivations
  }:
  let
    original' = if makeOriginalContentAddressable
      then original // {
        __contentAddressed = true;
        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
      }
      else original;

  in
    if cond
    then substituteForPrebuilt ((
      # `nixpkgs`, `original`, `prebuilts`, ...
      (builtins.removeAttrs args [ "cond" "makeOriginalContentAddressable" ])
    ) // (
      # If the `makeOriginalContentAddressable` is `true` then we'll force the
      # substitute derivation to also be content addressable.
      #
      # Otherwise we'll let the existing `produceContentAddressedDerivations`
      # value remain in effect (i.e. either the one passed in `args`, if
      # specified or the default).
      if makeOriginalContentAddressable
      then { produceContentAddressedDerivations = true; }
      else {}
    ))
    else original'
  ;

  createTarballWithPrebuiltSets =
  { nixpkgs
  , name ? "tarball-with-prebuilts"
  , base
    # { packageName => { system => derivation } }
    #
    # these will land in `sources.nix`
  , prebuiltSets ? {}
    # { path => path }
  , additions ? {}
    # [path]
  , exclude ? []
    # { path => [sed style replacement] list }
  , replacements ? []
  }:
  let
    prebuiltDir = "prebuilts";
  in
  derivation {
    inherit name additions exclude prebuiltSets base prebuiltDir;
    inherit (nixpkgs) system;
    __structuredAttrs = true;

    builder = "${nixpkgs.bash}/bin/bash";
    deps = with nixpkgs; [ coreutils python310 gnutar xz ];

    args = [(
      nixpkgs.writeScript "create-tarball.sh" ''
        . "''${NIX_ATTRS_SH_FILE}"
        for d in "''${deps[@]}"; do export PATH="''${PATH}:''${d}/bin"; done

        set -e

        out="''${outputs[out]}"

        staging="$(mktemp -d)"
        chmod u+rwx $staging
        staging="''${staging}/${name}"

        cp -R "$base" "$staging"
        chmod u+rwx "$staging"
        mkdir "$staging/$prebuiltDir"
        if [ -f "$staging/sources.nix" ]; then chmod u+rw "$staging/sources.nix"; fi

        (
          cd "$staging";
          python3 "${./create_tarball.py}" \
            "''${NIX_ATTRS_JSON_FILE}" \
            > sources.nix
        )

        mkdir -p $out
        tar rf "$out/archive.tar" -C "$staging/.." "$name" # --transform "s,^./,''${name}/,"
        xz "$out/archive.tar"

        # TODO: additions
        # TODO: excludes
      ''
    )];
  };

in {
  inherit prebuild restore;
  inherit prebuildNixpkg prebuildDerivations substituteForPrebuilt conditionallySubstitute;
  inherit createTarballWithPrebuiltSets;
}
