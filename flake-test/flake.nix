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
      np = import nixpkgs { system = "aarch64-darwin"; };
      target = np.nix;

      # useRecursiveNix = true;

      # targetDrvPath = builtins.unsafeDiscardStringContext (toString target.drvPath);
    in
      derivation {
        name = "test";
        system = "aarch64-darwin";
        builder = "${np.bash}/bin/bash";

        exportReferencesGraph.target = [ target ];
        __structuredAttrs = true;

        script = ./metadata.py;
        deps = with np; [ nix_2_4 coreutils jq python310 gnutar xz ];
        targetPath = target;
        args = [(

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
