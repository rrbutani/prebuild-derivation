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
    # Assert that all the derivations are for different systems?


  # TODO: strict/lenient mode on the "replace" step (i.e. warn on different inputs for the runtime version or error)
