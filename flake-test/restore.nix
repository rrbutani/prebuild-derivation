{
  dir,
  source_derivation,
  np,
}:
let
  archive = "${dir}/archive.tar.xz";
  metadata = builtins.fromJSON (builtins.readFile "${dir}/metadata.json");

  assertEq = got: expected: name:
    got == expected || builtins.throw "In substitution for ${source_derivation.name}: Expected `${expected}` for ${name} but got `${got}`!";

  _checks = [
    (assertMsg )
  ];

in
  derivation {
    name = "rg2";

    inherit _checks;

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = metadata.hash;

    # inherit (source_derivation)
  }

