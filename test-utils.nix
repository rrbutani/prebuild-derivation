{ nixpkgs
, prebuildNixpkg
, substituteForPrebuilt
}:
let
  checkDerivationsSame = a: b:
    let
      oneOutputOrMultiple = drv: if drv ? outputs
        then drv.outputs
        else [ drv.outputName ];
      aOutputs = oneOutputOrMultiple a;
      bOutputs = oneOutputOrMultiple b;

      isCA = x: x ? __contentAddressed;

      obfuscate = i: builtins.unsafeDiscardStringContext (
        builtins.concatStringsSep "%%" (
          builtins.filter
            (x: builtins.typeOf x != "list")
            (builtins.split "/" i)
        )
      );
      origA = obfuscate "${a}";
      origB = obfuscate "${b}";
    in
    derivation {
      name = "cmp-" +
        a.pname + (if (isCA a) then "-CA" else "") +
        "-" +
        b.pname + (if (isCA b) then "-CA" else "")
      ;
      builder = "${np.bash}/bin/bash";
      inherit (nixpkgs) system;

      _chkSameOutputs = aOutputs == bOutputs ||
        builtins.throw
          "outputs are not the same: `${toString aOutputs}` vs `${toString bOutputs}`";

      outputsToCompare = aOutputs;
      aOutputPaths = map (o: a.${o}) aOutputs;
      bOutputPaths = map (o: b.${o}) bOutputs;

      deps = with np; [ coreutils nix_2_4 ];
      args = [(
        np.writeScript "cmp.sh" ''
          for d in ''${deps[@]}; do export PATH="''${PATH}:''${d}/bin"; done

          outputs=($outputsToCompare)
          a=($aOutputPaths)
          b=($bOutputPaths)

          echo "checking ${a.name} (original) v. ${b.name} (substitute)"
          origA="${origA}"; origA=''${origA//\%\%//}
          origB="${origB}"; origB=''${origB//\%\%//}
          echo orig ${a} "(at eval: ''${origA})" \
            "(drv: ${builtins.unsafeDiscardStringContext a.drvPath})" \
            "(CA: ${toString (isCA a)})"
          echo subs ${b} "(at eval: ''${origB})" \
            "(drv: ${builtins.unsafeDiscardStringContext b.drvPath})" \
            "(CA: ${toString (isCA b)})"

          mismatched=""
          for ((i = 0; i < ''${#a[@]}; ++i)); do
            O=''${outputs[$i]}; A=''${a[$i]}; B=''${b[$i]};

            Ah=$(nix store dump-path $A | nix hash file /dev/stdin --base16)
            Bh=$(nix store dump-path $B | nix hash file /dev/stdin --base16)

            if ! [ "$Ah" == "$Bh" ]; then
              echo "Output \`$O\` mismatched!"
              echo "  - A: $A = $Ah"
              echo "  - B: $B = $Bh"
              mismatched="yes"
            fi
          done

          if [ $mismatched ]; then exit 4; fi

          mkdir -p $(dirname $out)
          touch $out
        ''
      )];
    };

  # Where `pkg` is either a string representing an attr or a function.
  getPkgDerivation = pkg:
    (if isString pkg then getAttr pkg else pkg) nixpkgs;

  roundtrip = pkg:
    let
      original = getPkgDerivation pkg;
      prebuilt = prebuildNixpkg { inherit nixpkgs pkg; };
      substitute = substituteForPrebuilt {
        inherit nixpkgs original; prebuilts = prebuilt;
        errorOnMismatch = { runtimeDeps = true; buildDeps = true; extraAttrs = true; };
        produceContentAddressedDerivations = true;
      };
    in substitute;

  check = pkg: checkDerivationsSame (getPkgDerivation pkg) (roundtrip pkg);

  # Forces the original derivation to be CA (content addressed).
  checkCA = pkg:
    let
      original = (getPkgDerivation pkg).overrideDerivation (old: {
        __contentAddressed = true;
        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
      });
    in
      check (_x: original);
in
{
  inherit roundtrip check checkCA;
}
