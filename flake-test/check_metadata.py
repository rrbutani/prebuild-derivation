#!/usr/bin/env python3

import sys, json, subprocess, pprint
_, prebuilt_metadata, drv, check_runtime_deps, check_build_deps, check_extra_attrs, check_for_extra_deps = sys.argv

drv = json.load(open(drv))
derivation_path = list(drv.items())[0][0]
drv = drv[derivation_path]
prebuilt_metadata = json.load(open(prebuilt_metadata))

check_extra_attrs    = check_extra_attrs    == "1"
check_build_deps     = check_build_deps     == "1"
check_runtime_deps   = check_runtime_deps   == "1"
check_for_extra_deps = check_for_extra_deps == "1"

if check_for_extra_deps and not (check_build_deps and check_runtime_deps):
    raise Exception("Cannot check for extra deps on the given derivation without checking for build and runtime dep mismatches!")

name = drv["env"]["pname"] if "pname" in drv["env"] else drv["env"]["name"]

def run(*cmd):
    p = subprocess.run(list(cmd), capture_output=True, check=True)
    return p.stdout.decode('utf-8')

def check(got, key):
    if got != (expected := prebuilt_metadata[key]):
        raise Exception(
            f"Found a mismatch in `{key}` while attempting to use a prebuilt for `{name}`:\n" +
            f"Expected:\n" +
            pprint.pformat(expected) +
            f"\n\n" +
            f"Got:\n" +
            pprint.pformat(got)
        )

if check_extra_attrs:
    attrs = ["inputSrcs", "system", "builder", "args", "env", "narHash"]
    for a in attrs:
        check(drv[a], a)

missing_deps = []
input_drvs = [ k for k, _ in drv["inputDrvs"].items() ]
if check_build_deps:
    for b in prebuilt_metadata["deps"]["build_only"]:
        if b not in input_drvs:
            missing_deps.append(("build", b))
        else:
            input_drvs.remove(b)

if check_runtime_deps:
    for r in prebuilt_metadata["deps"]["runtime"]["direct"]:
        if r not in input_drvs:
            missing_deps.append(("runtime", r))
        else:
            input_drvs.remove(r)

    # NOTE: we cannot actually check transitive deps easily but we can be pretty confident
    # they're "covered" by the direct deps.

if missing_deps:
    for (kind, dep) in missing_deps:
        print(
            f"Missing dep: {dep}\n" +
            f"  - The prebuilt was built with this *{kind}* dep but the given derivation does not have it.\n",
            file = sys.stderr
        )

    raise Exception(f"{len(missing_deps)} deps (listed above) are missing from the given derivation.")

if check_build_deps and check_runtime_deps and check_for_extra_deps:
    # Check that there are no extra deps specified for the given derivation.
    if input_drvs:
        raise Exception(
            "Found dependencies that the given derivation has that the prebuild does not:\n" +
            pprint.pformat(input_drvs)
        )
