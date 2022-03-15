# substitute:
# compute deps for original (nix show-derivation on the drvPath – passed in with unsafeDiscardStringContext)
#   - check that deps include all the runtime deps, conditionally
#   - check that deps include all the build deps, conditionally
# extract from the actual thing (fixed output drv, output hash, etc)
#
# NOTE: the above will do drvPath comparison and not output path comparison (except for fixedOutput drvs, I think)
# this is fine for input-addressable derivations (equivalent) and also for content-addressed derivations

# TODO: record original output paths, rewrite to the new ones in the restore phase

{ dir
, np
, sourceDerivation
, checkRuntimeDeps ? true
, checkBuildDeps ? false
, checkExtraAttrs ? false
, useContentAddressedDerivations ? true
}:
let
  archiveFile = "${dir}/archive.tar.xz";
  metadataFile = "${dir}/metadata.json";

  metadata = builtins.fromJSON (builtins.readFile metadataFile);

  checkForExtraDeps = checkRuntimeDeps && checkBuildDeps && checkExtraAttrs;

  # We specifically do *not* want to build the original derivation. We are
  # just trying to figure out what deps it would be built with. Because we
  # have the derivation in hand we can be confident that the .drv file for
  # it exists in the nix store.
  #
  # Stripping the string context here ensures that we do not cause nix to
  # build the derivation.
  originalDerivationIsContentAddressable = sourceDerivation ? __contentAddressed;
  originalDerivationPath = builtins.unsafeDiscardStringContext (
    if originalDerivationIsContentAddressable
    then (toString sourceDerivation.drvPath)
    else (toString sourceDerivation)
  );

  noOverride = builtins.throw "Cannot override a prebuilt derivation, sorry!";
  attrsToRestore = {
      override = noOverride;
      overrideAttrs = noOverride;
      overrideDerivation = noOverride;
      passthru = builtins.throw "Passthrus are not supported with prebuilt derivations, sorry!";
    }
    // (if sourceDerivation ? meta then { meta = sourceDerivation.meta // { prebuilt = true; }; } else {});

  # multiOutput = sourceDerivation ? outputs && ((builtins.length sourceDerivation.outputs) > 1);

  args =
    sourceDerivation.drvAttrs // {

    # To preserve the string context for these attrs, in case they contain runtime deps:
    _originalBuilder = sourceDerivation.builder;
    _originalArgs = if sourceDerivation ? args then sourceDerivation.args else null;

    _prebuildRestoreDeps = with np; [ nix_2_4 coreutils python310 gnutar xz ];

    builder = "${np.bash}/bin/bash";
    args = [(
      np.writeScript "restore.sh" ''
        for d in ''${_prebuildRestoreDeps[@]}; do export PATH="''${PATH}:''${d}/bin"; done

        nix show-derivation ${originalDerivationPath} > drv.json
        python3 "${./check_metadata.py}" \
          ${metadataFile} \
          drv.json \
          "${toString checkRuntimeDeps}" \
          "${toString checkBuildDeps}" \
          "${toString checkExtraAttrs}" \
          "${toString checkForExtraDeps}" \
        || exit 5

        echo "restoring from archive: ${archiveFile}"
        for output in ''${outputs}; do
          echo $output to ''${!output}
          mkdir -p ''${!output}

          tar xf "${archiveFile}" \
            -C ''${!output} \
            $output \
            --transform "s,^''${output}/,," \
            --delay-directory-restore \
            # --verbose \
            # --show-transformed-names
            # --absolute-names \
        done
      ''
    )];
  } // (
    # if multiOutput
    # then (
      # Otherwise we have to fall back to being content addressed, if that's enabled:
      if useContentAddressedDerivations
      then {
        __contentAddressed = true;
        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
      }
      # Or just being a regular input-addressed derivation (in this case, the prebuilt
      # derivation that we are producing is *certain* to not match the output path of
      # the original derivation):
      else {
        _output = builtins.trace
          "Warning: falling back to an input-addressed derivation for the substitute" 0;
      }
    # )
    # else {
    #   # If we do not have multiple outputs we can be a fixed output derivation.
    #   outputHash = metadata.hash;
    #   outputHashMode = "recursive";
    #   outputHashAlgo = "sha256";
    # }
  );
in
  derivation args // attrsToRestore
