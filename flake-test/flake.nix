{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-21.11;
  };
  outputs = { self, nixpkgs }: let
    system = "aarch64-darwin";
    np = import nixpkgs { inherit system; };
    target = np.nix;

    # prebuild:
    # store runtime deps (from exportReferencesGraph)
    # store build deps (from `show-derivation` on the target)
    # store the actual thing (nix dump-path -- target, piped into xz)
    #   - compute the checksum and store it?

    # ~secret~ string context functions: https://github.com/NixOS/nix/commit/1d757292d0cb78beec32fcdfe15c2944a4bc4a95#diff-f9b278c45a70ce046ba391eaca009baf0f306a99c2328e1a651bbb36cf22d802

    # substitute:
    # compute deps for original (nix show-derivation on the drvPath – passed in with unsafeDiscardStringContext)
    #   - check that deps include all the runtime deps, conditionally
    #   - check that deps include all the build deps, conditionally
    # extract from the actual thing (fixed output drv, output hash, etc)

    # NOTE: the above will do drvPath comparison and not output path comparison (except for fixedOutput drvs, I think)
    # this is fine for input-addressable derivations (equivalent) and also for content-addressed derivations

    prebuild =
      { target
      , outputsToPackage ? null
      }:
    let
      targetOutputList = if outputsToPackage == null
        then if target ? outputs then target.outputs else [ target.outputName ]
        else outputsToPackage;

      # (this is really a job for filterAttrs from nixpkgs.lib)
      targetOutputs = builtins.listToAttrs (
        builtins.map (
          output: { name = output; value = target.${output}; }
        ) targetOutputList
      );
    in
    derivation {
      name = if target ? pname && target ? version then
        target.pname + "-prebuilt-" + target.version
      else
        target.name + "-prebuilt";

      inherit system;
      builder = "${np.bash}/bin/bash";

      exportReferencesGraph.target = [ target ];
      __structuredAttrs = true;

      deps = with np; [ nix_2_4 coreutils jq python310 gnutar xz ];
      targetPath = target.all;
      inherit targetOutputs;
      args = [(
        np.writeScript "prebuild.sh" ''
          . "''${NIX_ATTRS_SH_FILE}"
          for d in "''${deps[@]}"; do export PATH="''${PATH}:''${d}/bin"; done

          getAttr() { jq -r "''${@}" <"''${NIX_ATTRS_JSON_FILE}"; }

          out="''${outputs[out]}";
          mkdir -p $out

          nix show-derivation ''${targetPath} > drv.json
          getAttr ".target | .[] | select(.path == \"$targetPath\")" > runtime.json

          python3 "${./grab_metadata.py}" \
              runtime.json drv.json \
            | jq > $out/metadata.json

          for output_name in "''${!targetOutputs[@]}"; do
            echo $output_name ''${targetOutputs[$output_name]}
            tar rf $out/archive.tar -C "''${targetOutputs[$output_name]}" . --transform "s,^,''${output_name}/,"
          done

          xz $out/archive.tar
        ''
      )];
    };

    restore =
      { dir
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
      originalDerivationPath = builtins.unsafeDiscardStringContext (toString sourceDerivation);

      noOverride = builtins.throw "Cannot override a prebuilt derivation, sorry!";
      attrsToRestore = {
          override = noOverride;
          overrideAttrs = noOverride;
          overrideDerivation = noOverride;
          passthru = builtins.throw "Passthrus are not supported with prebuilt derivations, sorry!";
        }
        // (if sourceDerivation ? meta then { meta = sourceDerivation.meta // { prebuilt = true; }; } else {});

      multiOutput = sourceDerivation ? outputs && ((builtins.length sourceDerivation.outputs) > 1);

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
              "${toString checkForExtraDeps}"

            for output in ''${outputs}; do
              echo $output to ''${!output}
              tar xf "${archiveFile}" $output \
                --transform "s,^''${output}/,''${!output}/," \
                --absolute-names \
                # --verbose \
                # --show-transformed-names
            done
          ''
        )];
      } // (
        if multiOutput
        then
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
          else builtins.trace "Warning: falling back to an input-addressed derivation for the substitute" {}
        else {
          # If we do not have multiple outputs we can be a fixed output derivation.
          outputHash = metadata.hash;
          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
        }
      );
    in
      derivation args // attrsToRestore
    ;

          # NOTE: the above will do drvPath comparison and not output path comparison (except for fixedOutput drvs, I think)
          # this is fine for input-addressable derivations (equivalent) and also for content-addressed derivations

          np.writeScript "test.sh" ''
            # env

            . "''${NIX_ATTRS_SH_FILE}"
            for d in "''${deps[@]}"; do export PATH="''${PATH}:''${d}/bin"; done

            getAttr() { jq -r "''${@}" <"''${NIX_ATTRS_JSON_FILE}"; }

            out="''${outputs[out]}";
            mkdir -p $out

            nix show-derivation ${target} > drv.json
            getAttr ".target | .[] | select(.path == \"$targetPath\")" > runtime.json

            python3 ${./metadata.py} \
                runtime.json drv.json \
              | jq > $out/metadata.json

            tar cJf $out/archive.tar.xz -C ${target} .
          ''
        )];
      };
  };
}
