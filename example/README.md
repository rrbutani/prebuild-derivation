
`example.cc` is the file that we do not want to be publicly visible to users of this flake
runtime dep on "hello"

so, this flake has a target that:
  - builds a prebuilt for `example`, the derivation that builds `example.cc`
  - creates a new _version_ of this flake (as a tarball) that includes the prebuilt
    * and also alters `source.nix` to tell this flake to use prebuilts
    * and strips `example.cc` out of this flake (because it's not copied in)


---

```bash
nix build .#withPrebuilts
nix flake run file://$(realpath result/archive.tar.xz)
```
