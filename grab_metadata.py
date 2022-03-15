#!/usr/bin/env python3

import sys, json, subprocess
_, runtime_info, drv = sys.argv

drv = json.load(open(drv))
derivation_path = list(drv.items())[0][0]
drv = drv[derivation_path]
runtime_info = json.load(open(runtime_info))

def run(*cmd):
    p = subprocess.run(list(cmd), capture_output=True, check=True)
    return p.stdout.decode('utf-8')

def get_derivation(dep):
    try:
        return list(json.loads(run("nix", "show-derivation", dep)).items())[0][0]
    except subprocess.CalledProcessError as e:
        if "does not have a known deriver" in str(e.stderr.decode('utf-8')):
            # This is to handle CA derivations:
            res = run("nix-store", "-qd", dep)
            if not "unknown" in res:
                return res.strip()

        raise e

out = {}
copy = lambda key, src = drv: out.update({ key: src[key] })

# Note: specifically not copying `outputs` here.
copy("inputSrcs")
copy("system")
copy("builder")
copy("args")
copy("env")
copy("narHash", runtime_info)

out["hash"] = run("nix", "hash", "to-base16", runtime_info["narHash"]).strip()

# Can't call `nix-store` inside recursive nix, I think.
"""
dep_closure = lambda d: run("nix-store", "-q", "--requisites", d).split() # TODO: should probably memoize..
full_derivation_dep_closure = dep_closure(derivation_path)
"""

runtime_deps = runtime_info["references"]
transitive_runtime_deps = []
direct_runtime_deps = []
build_only_deps = [k for k, _ in drv["inputDrvs"].items()]
for r in runtime_deps:
    # Convert to .drv path:
    r = get_derivation(r)
    # r = list(json.loads(run("nix", "show-derivation", r)).items())[0][0]

    # Runtime deps that show up in the inputs are *direct* deps
    if r in build_only_deps:
        direct_runtime_deps.append(r)
        build_only_deps.remove(r)
    else:
        # Runtime deps that do not must be *transitive* deps.
        transitive_runtime_deps.append(r)

        # Just to be sure we'll check that this dep is in the build dep
        # closure:
        """
        assert r in full_derivation_dep_closure
        """

# Just to be sure, we'll check that all the transitive deps are "covered"
# by one of the direct deps:
"""
for t in transitive_runtime_deps:
    assert any(
        t in dep_closure(d)
        for d in direct_runtime_deps
    )
"""

direct_runtime_deps.sort()
transitive_runtime_deps.sort()
build_only_deps.sort()

out["deps"] = {
    "runtime": {
        "direct": direct_runtime_deps,
        "transitive": transitive_runtime_deps,
    },
    "build_only": build_only_deps,
}

print(json.dumps(out, sort_keys=True))
