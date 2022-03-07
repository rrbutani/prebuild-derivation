{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-21.11;
  };
  outputs = { self, nixpkgs }: {

    defaultPackage.aarch64-darwin =
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
        # args = [ "show-derivation" (toString np.neofetch) ];
        # [ "show-derivation" (builtins.unsafeDiscardStringContext (toString np.neofetch.drvPath)) ];

        exportReferencesGraph.target = [ target ];
        __structuredAttrs = true;

        script = ./metadata.py;
        deps = with np; [ nix_2_4 coreutils jq python310 ];
        targetPath = target;
        # inherit useRecursiveNix; # TODO!
        args = [(

            # echo -ne ${target} "\n" ${targetDrvPath};
            # nix show-derivation ${target} | tee /dev/stderr | jq > $out/target.json

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

            # nix-store -q /nix/store/53dya616r0j6da1jfmp4k91hrr7nsj07-ripgrep-13.0.0.drv || exit 4
            # nix-store -q -R /nix/store/53dya616r0j6da1jfmp4k91hrr7nsj07-ripgrep-13.0.0.drv

            # nix show-derivation /nix/store/0x9a5qdrzh2c17nbbd6wdpkrp1pywd2v-apple-framework-CoreFoundation-11.0.0

            # echo what the
            # exit 89

            python3 ${./metadata.py} \
                runtime.json drv.json \
              | jq > $out/metadata.json

            # nix show-derivation ${target} \
            #   | tee /dev/stderr \
            #   | python3 <(cat <<-EOF
          	# 			import sys, json
          	# 			inp = json.loads(sys.stdin.read())["${target}"]
          	# 			out = {}

          	# 			copy = lambda key: out[key] = inp[key]
          	# 			copy("inputSrcs")
          	# 			# copy("inputDrvs")
          	# 			copy("system")
          	# 			copy("builder")
          	# 			copy("env")

          	# 			copy("env")

          	# 			print(json.dumps(inp))
          	# 		EOF
            #     ) \
            #   | jq > $out/drv.json

            # # getAttr .target
            # # echo $targetPath
            # getAttr ".target | .[] | select(.path == \"$targetPath\")" > $out/runtime.json

            # hash=$(jq -r .narHash <$out/runtime.json | cut -d':' -f2)
            # echo $hash
          ''
        )];
      };
  };
}
