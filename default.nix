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
}:

let
  # Takes a nixpkgs instance, a name of a package or a function that gets the
  # package from a nixpkgs instance, and a list of systems (defaults to
  # defaultSystems).
  preBuildNixpkg =
    {
      nixpkgs,
      pkg,
      systemNames ? defaultSystems,
    }:
    let
      # If `pkg` isn't a function, turn it into a function that looks up the
      # `pkg` field:
      pkg' = if isString pkg then getAttr pkg else pkg;
    in
    preBuildDerivations (map (sys: pkg' nixpkgs.${sys}) systemNames)
  ;


  # Takes a list of derivations.
  #
  # The list of derivations should be for the different systems.
  #
  # Produces a tarball (has the different systems, etc.).
  preBuildDerivations = { derivations }:
    # Assert that all the derivations are for different systems (i.e. only one derivation per system)

    # Produces a tarball with:
    # ```
    # |- <system name>
    # |  |- inputs.json (details about the transitive closure of the derivation)
    # |  |- outputs
    # |     |- lib
    # |     |- bin
    # |     |- doc
    # |     |- ...
    # |- ...
    # ```

    # TODO: not sure what the best way to get `inputs.json` is; perhaps `exportReferencesGraph`?

    # TODO: can we just use the NAR for the derivation's store path somehow?

    ;

  # TODO: strict/lenient mode on the "replace" step (i.e. warn on different inputs for the runtime version or error)


  # Takes a derivation and a tarball.
  #
  # Gives back a new derivation that can be used in lieu of the original but uses the prebuilt artifacts from the
  # tarball.
  substituteForPrebuilt = { original, tarball, errorOnPrebuiltMismatch ? false }:
    # Assert that original is a derivation and that `tarball` is a path/derivation.
    #
    # Produce a new derivation that has the same outs but extracts them from the tarball.
    # Have the derivation steal test/check phases? (or just override the fetch/configure/build phases, etc.)
    #
    # Upfront check that the derivation's closure etc matches; warn if not, error if the flag above tells us
    # to.

    # TODO: should we have this set `outputHash`? might be tricky to get `preBuild` to spit these out (a post processing step
    # that emits a nix file that we can then import here?)
    #
    # maybe make it an optional thing?
    #
    # or, don't take a tarball but a path that we'll append the package name + "-hash.nix"/".tar.gz" to
    #
    # and have preBuildDerivations spit this directory out
  ;
in {
  inherit preBuildNixpkg preBuildDerivations substituteForPrebuilt;
}
