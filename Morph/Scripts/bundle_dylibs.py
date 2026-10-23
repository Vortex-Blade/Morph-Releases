#!/usr/bin/env python3
"""Copy non-system Mach-O dependencies of bundled helpers and rewrite load paths.

Requires macOS otool and install_name_tool. This does not modify LibreOffice's
own app bundle, whose internal runtime is already included by ditto.
"""
import os
import subprocess
import sys
from pathlib import Path

contents = Path(sys.argv[1]); helpers = contents / "Helpers"; frameworks = contents / "Frameworks"
originals = [Path(x).resolve() for x in sys.argv[2:]]


def call(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT)


def deps(path):
    lines = call("otool", "-L", str(path)).splitlines()[1:]
    return [line.strip().split(" (compatibility version")[0].split(" (current version")[0]
            for line in lines if line.strip()]


def resolve(dep, origin):
    if dep.startswith("/usr/lib/") or dep.startswith("/System/Library/"):
        return None
    if dep.startswith("@rpath/"):
        # Homebrew binaries generally embed /opt/homebrew/lib and Cellar rpaths.
        for root in [origin.parent, Path("/opt/homebrew/lib"), Path("/usr/local/lib")]:
            candidate = root / dep[len("@rpath/"):]
            if candidate.exists(): return candidate.resolve()
        raise RuntimeError(f"Onopgeloste @rpath-dependency: {dep} in {origin}")
    if dep.startswith("@loader_path/"):
        return (origin.parent / dep[len("@loader_path/"):]).resolve()
    if dep.startswith("@executable_path/"):
        return (originals[0].parent / dep[len("@executable_path/"):]).resolve()
    if dep.startswith("/"):
        p = Path(dep)
        if p.exists(): return p.resolve()
        raise RuntimeError(f"Dependency niet gevonden: {dep}")
    raise RuntimeError(f"Onbekende dependency: {dep} in {origin}")

# Map each original library to a bundled file. Names include a sequence number
# to avoid clashes between different libraries with the same basename.
found = {}; queue = list(originals)
while queue:
    origin = queue.pop(0)
    for dep in deps(origin):
        lib = resolve(dep, origin)
        if lib is None or lib in found: continue
        if not lib.is_file(): raise RuntimeError(f"Niet gevonden: {lib}")
        target = frameworks / f"lib{len(found):03d}_{lib.name}"
        target.write_bytes(lib.read_bytes())
        target.chmod(0o755)
        found[lib] = target
        queue.append(lib)

# Patch each copied Mach-O file. The executable uses @executable_path/../Frameworks;
# libraries use @loader_path because they live directly in Frameworks.
for original, packaged in [(originals[0], helpers / "ffmpeg"), (originals[1], helpers / "qpdf"), *found.items()]:
    for dep in deps(original):
        lib = resolve(dep, original)
        if lib is None: continue
        if lib not in found: raise RuntimeError(f"Niet ingepakte dependency: {lib}")
        target = found[lib]
        replacement = ("@loader_path/" if packaged.parent == frameworks
                       else "@executable_path/../Frameworks/") + target.name
        subprocess.run(["install_name_tool", "-change", dep, replacement, str(packaged)], check=True)
    if packaged.parent == frameworks:
        subprocess.run(["install_name_tool", "-id", "@loader_path/" + packaged.name, str(packaged)], check=True)
print(f"Ingepakt: {len(found)} dynamische bibliotheken")
