{ nixpkgs }:
let
  prebuild = {
    original
  }: let
    args = rec {
      name = if original ? pname && original ? version then
        original.pname + "-prebuilt-" + original.version
      else
        original.name + "-prebuilt";

      inherit (original) system;

      # !!! not sure how this will interact with content addressed derivations; i.e. will `exportReferencesGraph`
      # give us the runtime dependencies graph for a content addressed derivation even though the store path we
      # have at eval time is not accurate?
      #
      # see: https://github.com/tweag/rfcs/blob/cas-rfc/rfcs/0062-content-addressed-paths.md#drawbacks

      # see: https://github.com/NixOS/nix/issues/1245
      # see: https://nixos.org/manual/nix/unstable/expressions/advanced-attributes.html
      #
      # we get both the runtime dependencies of the derivation (a subset of the build time
      # deps) and the *transitive* closure of the derivation's build time dependencies
      exportReferencesGraph = {
        runtime = [ original ];

        # note: decided we don't need this; we don't want to go fetch the transitive closure of
        # everything `original` depends on when making this pre-built.
        #
        # instead we can rely on either the hash in original's `drvPath` or in original's output
        # path to serve as a proxy for "thing that represents the transitive build environment
        # for `original`"
        #
        # we'll use `drvPath` because, for content addressed derivations, this will still reflect
        # the build env even though the output path will not (TODO: whether this is the right
        # thing to do here is debatable)
        #
        # storing a copy of the derivation also lets us do better checking at substitution time
        # "build-time" original.drvPath
      };
      # exportReferencesGraph.runtime = [original];

      # see: https://github.com/NixOS/nix/issues/1134
      # see: https://github.com/NixOS/nix/commit/1351b0df87a0984914769c5dc76489618b3a3fec
      # see: https://github.com/NixOS/nix/commit/c2b0d8749f7e77afc1c4b3e8dd36b7ee9720af4a#commitcomment-27732213
      # see: https://nixos.mayflower.consulting/blog/2020/01/20/structured-attrs/
      __structuredAttrs = true;
      # __json = true;

      deps = [nixpkgs.jq nixpkgs.coreutils];

      builder = "${nixpkgs.bash}/bin/bash";
      args = [ ./prebuild.sh ];

      outputs = [ "tarball" "metadata" ];

      inherit original;
      originalDrvPath = builtins.readFile original.drvPath;
    };
    args' = builtins.trace args args;
  in
    derivation args'
  ;

  # NOTE: not overrideable (does not have an `override` attr).
  # I think this makes sense (anything that you override won't take anyways, we're using
  # a prebuilt...)
  #
  # TODO: We may want to expose an `override` attr that errors instead of just not having one
  # though. (`override = throw "cannot override a prebuilt..."`)
  substitute = {
    original, prebuilts,
  }:
  let
    a = 9;
  in
    a
  ;
in {
  inherit prebuild substitute;
}
