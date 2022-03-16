#!/usr/bin/env python3

import sys, json, os, os.path as p, shutil
from typing import Dict
_, json_attrs = sys.argv

newl = "\n"

PkgName, System, PrebuiltDrvPath, TarballRelativePath = str, str, str, str
def copy_prebuilt_sets(prebuilt_sets: Dict[PkgName, Dict[System, PrebuiltDrvPath]], prebuilt_dir: str) -> Dict[PkgName, Dict[System, TarballRelativePath]]:
    sources = {}

    for pkg, prebuilts in prebuilt_sets.items():
        sources[pkg] = {}

        pkg_base = p.join(prebuilt_dir, pkg)
        os.mkdir(pkg_base)
        for system, drv_path in prebuilts.items():
            dest = p.join(pkg_base, system)
            sources[pkg][system] = dest

            shutil.copytree(drv_path, dest)

    return sources

def generate_nix_sources_file(sources: Dict[PkgName, Dict[System, TarballRelativePath]]) -> str:
    def format_prebuilt(system, path):
        return f"""\n    "{system}" = ./{path};"""
    def format_prebuilts(name, prebuilts):
        return (
            f"""\n  {name} = {{""" +
            ''.join(format_prebuilt(s, p) for s, p in prebuilts.items()) +
            f"""{ newl if len(prebuilts) else ""}  }};"""
        )

    return (
f"""{{{ ''.join(format_prebuilts(n, pb) for n, pb in sources.items()) }
  usePrebuilts = true;
}}""")

attrs = json.load(open(json_attrs))

prebuilt_sets = attrs["prebuiltSets"]
prebuilt_dir = attrs["prebuiltDir"]

sources = copy_prebuilt_sets(prebuilt_sets, prebuilt_dir)
print(generate_nix_sources_file(sources))
