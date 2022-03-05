name's bad, sorry


from Other:
```
TODO: generalized thing that lets you build a derivation and turn it into artifacts and then makes another derivation with the same runtime deps as the actual derivation but none of the build deps (just goes and uses the pre-built artifacts as a source).
  - these need to be separate steps; one in CI at "release time" the other at runtime. the first step probably needs to dump the derivation's metadata somehow? or at runtime we take the actual derivation and Transform it. probably the latter
  - just have a conditional postprocessing step that runs on the derivations for llvm, etc.
    + "conditionallySubstituteForPreBuilt", etc.
```

---

# what

a thing with some machinery to let you replace a derivation with a prebuilt version of it (i.e. does not need access to the derivation's build dependencies) in a fashion that's fairly transparent
# why

odd bad situations in which you *cannot* distribute source code for a package
but still want to build it using nix

want a little more generality (i.e. permissive mode that allows for small mismatches in build deps)
want to be able to live inside nix, without manipulating the nix store manually if possible (i.e. loading something into the store manually)

## why not just provide users with a nix cache?

depending on your use case this may be sufficient.

for example, you can:
  - provide users with a build cache that does *not* contain source code/other artifacts that you do not want to be publicly accessible
  - rely on substitution to provide users with a built version of the derivation despite them not having access to the source artifacts
  - impose some kind of protection on whatever mechanism is used to get the source artifacts without altering the derivation that yields the artifact
    * for example, make the git repo where source is fetched from private, etc. (this is tricky because it's hard to do in a way that's pure and that also doesn't break – builtins.fetchGit for example runs at eval time)
    * the "don't alter the derivation that yields the artifact" bit is important because otherwise your cached derivation won't register as a substitute for whatever the user ultimately tries to build

<!-- ### example
this *does* work; here's an example:
```shell

``` -->



### downsides
as you've probably guessed, this *is* somewhat brittle
beyond requiring you to stand up a cache and requiring that all users of the derivation (even transitively) have that cache (and being careful to not put the "secret" artifacts in the cache)

it also is a little fragile (changes to the derivation that don't actually invoke changing the artifact that's produced *will* result in complete breakage instead of just a rebuild. this is a good default and is _normally_ the behavior you want but when the failure mode is "can't run the thing at all" instead of just "you must suffer a rebuild" **and** when you have some additional knowledge about the nature of a package's dependencies (i.e. i know that the version of `coreutils` – a build dep – used by my package's build has no real implications on the final artifact that's produced) you sometimes want a knob that lets you turn this behavior off). note that this mostly only applies to build time deps. wanting to allow for different runtime deps at "substitution time" is an extreme edge case and the default behavior of this package is to error if the runtime dependencies of the prebuilt do not match those it was built against

all this is to say that
when you rely on nix caching based substitution, you require users to have the exact same set of transitive build deps
this package relaxes that requirement though it (by default) does still require you to have the same set of _runtime deps_ (as you'd want almost always)
(note that the above is still true if your original derivation is content addressed, I believe; for content addressable derivations, [the derivation's hash is used to attempt cache substitution](https://github.com/tweag/rfcs/blob/cas-rfc/rfcs/0062-content-addressed-paths.md#basic-principles); it's only once you do the rebuild of the CA derivation that you can have downstream early cutoff optimization)

in the general case this is not useful and is a bad default but when you have some knowledge about your build deps (or are reasonably confident that there are no build dep changes that make sense for your project/users) it can be handy to be able to just Ignore build dep changes

## why not have users just copy in store paths?

this works for some use cases too. In fact [`requireFile`](https://github.com/NixOS/nixpkgs/blob/989e6b7bc134dfc47a6daf2f5f2b6f4356040c5d/pkgs/build-support/trivial-builders.nix#L680) in `nixpkgs` (which works by creating a fixed output derivation with an output hash equal to that of the prebuilt artifact that errors if the derivation is ever realized – the idea being that the derivation's realization must be preempted by the existence of the artifact in the nix store) does exactly this

however, it shares the same downsides as requiring users to have a particular nix cache, including that it is harder to "live in nix" this way. you'd need to compute the hash of your artifact, create tarballs for it, and then instruct users to load it in, etc.

## why not just distribute built artifacts?

i.e. with [`nix-bundle`](TODO)

this also works for some use cases!

the caveat here is that this does not work if you want to live inside nix; i.e. if you want users to be able to depend on your flake or start up a dev shell, etc. instead of just running binaries

## why not use IFD?

TODO
I think the idea is to conditionally import from either a tarball or to encapsulate actually doing the building in IFD? as a way to paper over the differences between the two routes
I think you still run into the yuckiness with input addressed vs. not

I think i'm really just describing an alternative implementation of this package that's worse; nvm

# how

(feel free to skip this; it's not stuff that necessary to know to just use this package)

TODO
# caveats

unless you alter the derivations you are seeking to replace with prebuilts to be content addressable, using a prebuilt in lieu of the original derivation in a dependent derivation will trigger a rebuild

put differently, the prebuilt's derivation will *not* have the same nix store output path as the original unless you switch the original to be content addressed

even though the prebuilt derivation's output is identical to that of the original, it's _derivation_ is not; if the original derivation is _input addressed_ (the default) this means that the original derivation will have an output path that does not reflect the ultimate contents produced by it. hence the mismatch

this is in contrast to the methods discussed above; simply requiring that users load some paths into their nix in lieu of building them themselves means that the output path of the artifact you're trying to "prebuild" is the same regardless (though, it's worth noting that for the "copy in store paths" path you'd need some additional machinery to make this happen; you run into the same issue wrt to the normal route having an input addressed hash). even with the "use a cache" route you need to exercise some care to have your derivations line up while not making whatever it is you want to hide public (i.e. you can't remove the source files because that'd change the drvs of the downstream things if referenced by path and you can't use `builtins.fetchGit` because it runs at eval time so you probably want `nixpkgs.fetchgit` with a sha256 but that doesn't have access to your environment meaning private repos are hard, etc, etc).


# usage

TODO

link to the example
call out the machinery for generating a new flake

# should I use this

As you've probably gathered if you've read through the above, the answer is almost certainly "absolutely not". If you really want to provide your users with a nix expression **and** cannot live with the added overhead of requiring users to load some things in their nix store **and** really want to use nix to build and distribute whatever artifact it is you're trying to prebuild (instead of producing tarballs with no deps, etc.) then this package is for you. But otherwise, you're definitely better served by the other options [discussed in the why section](#why).

---


misc:
  - reexport source dir as derivation

want to use nars but can't figure out a good way to do this from within nix expressions
want to use the output of `show-derivation` but can't figure out if there already is a nix expression equivalent
