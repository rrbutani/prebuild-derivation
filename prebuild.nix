# prebuild:
# store runtime deps (from exportReferencesGraph)
# store build deps (from `show-derivation` on the target)
# store the actual thing (nix dump-path -- target, piped into xz)

# ~secret~ string context functions: https://github.com/NixOS/nix/commit/1d757292d0cb78beec32fcdfe15c2944a4bc4a95#diff-f9b278c45a70ce046ba391eaca009baf0f306a99c2328e1a651bbb36cf22d802

{ target
, np
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

  inherit (np) system;
  builder = "${np.bash}/bin/bash";

  exportReferencesGraph.target = [ target ];
  __structuredAttrs = true;

  deps = with np; [ nix_2_4 coreutils jq python310 gnutar xz ];
  targetPath = target.all;
  _backupDrvPath = builtins.unsafeDiscardStringContext target.drvPath;
  _targetIsContentAddressed = target ? __contentAddressed;
  inherit targetOutputs;
  args = [(
    np.writeScript "prebuild.sh" ''
      . "''${NIX_ATTRS_SH_FILE}"
      for d in "''${deps[@]}"; do export PATH="''${PATH}:''${d}/bin"; done

      getAttr() { jq -r "''${@}" <"''${NIX_ATTRS_JSON_FILE}"; }

      out="''${outputs[out]}";
      mkdir -p $out

      nix show-derivation ''${targetPath} > drv.json 2>/dev/null || {
        if [ $_targetIsContentAddressed ]; then
          nix show-derivation ''${_backupDrvPath} > drv.json
        else
          exit 4;
        fi
      }
      getAttr ".target | .[] | select(.path == \"$targetPath\")" > runtime.json

      python3 "${./grab_metadata.py}" \
          runtime.json drv.json \
        | jq > $out/metadata.json

      echo "archiving ${target.name}:"
      for output_name in "''${!targetOutputs[@]}"; do
        echo $output_name from ''${targetOutputs[$output_name]}
        tar rf $out/archive.tar -C "''${targetOutputs[$output_name]}" . --transform "s,^./,''${output_name}/,"
      done

      xz $out/archive.tar
    ''
  )];
}
