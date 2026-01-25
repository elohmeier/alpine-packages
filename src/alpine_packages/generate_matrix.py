"""Generate filtered build matrix from melange YAML files."""

import json
import os
import subprocess
import sys
import tarfile
import urllib.request
from io import BytesIO
from pathlib import Path

import yaml


def parse_yaml(path: Path) -> dict:
    with open(path) as f:
        return yaml.safe_load(f)


def get_local_packages() -> set[str]:
    """Get package names that exist in this repo."""
    return {f.stem for f in Path(".").glob("*.yaml") if not f.name.startswith(".")}


def extract_dependencies(
    pkg_data: dict, local_packages: set[str]
) -> tuple[list[str], list[str]]:
    """Extract local dependencies from package data.

    Returns:
        Tuple of (build_time_deps, runtime_deps)
    """
    build_deps = set()
    runtime_deps = set()

    # Runtime dependencies
    for dep in pkg_data.get("package", {}).get("dependencies", {}).get("runtime", []):
        if dep in local_packages:
            runtime_deps.add(dep)

    # Build dependencies
    for dep in pkg_data.get("environment", {}).get("contents", {}).get("packages", []):
        if dep in local_packages:
            build_deps.add(dep)

    return sorted(build_deps), sorted(runtime_deps)


def compute_phases(packages: dict, already_built: set[str]) -> list[list[str]]:
    """Compute build phases using topological sort.

    Args:
        packages: Dict of packages that need to be built
        already_built: Set of package names that are already published (don't need building)
    """
    phases = []
    remaining = set(packages.keys())
    built = already_built.copy()  # Start with already-published packages

    while remaining:
        phase = [n for n in remaining if set(packages[n]["local_dependencies"]) <= built]
        if not phase:
            print(f"Error: circular dependency among {remaining}", file=sys.stderr)
            sys.exit(1)
        phases.append(sorted(phase))
        remaining -= set(phase)
        built |= set(phase)

    return phases


def get_changed_files(base_ref: str | None) -> set[str] | None:
    """Get changed files using git. Returns None if no base_ref."""
    if not base_ref:
        return None  # No base = use version comparison only
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", base_ref, "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        )
        return set(result.stdout.strip().split("\n")) if result.stdout.strip() else set()
    except subprocess.CalledProcessError:
        return None


def get_published_versions(repo_url: str) -> dict[str, str]:
    """Fetch published versions from APKINDEX."""
    versions = {}
    for arch in ["aarch64", "x86_64"]:  # Check one arch, versions should match
        try:
            url = f"{repo_url}/{arch}/APKINDEX.tar.gz"
            with urllib.request.urlopen(url, timeout=10) as resp:
                tar_data = BytesIO(resp.read())
            with tarfile.open(fileobj=tar_data, mode="r:gz") as tar:
                apkindex = tar.extractfile("APKINDEX")
                if apkindex:
                    content = apkindex.read().decode()
                    pkg, ver = None, None
                    for line in content.split("\n"):
                        if line.startswith("P:"):
                            pkg = line[2:]
                        elif line.startswith("V:"):
                            ver = line[2:]
                        elif line == "" and pkg and ver:
                            versions[pkg] = ver
                            pkg, ver = None, None
            break  # Got versions from one arch
        except Exception:
            continue
    return versions


def package_needs_build(
    name: str,
    pkg: dict,
    changed_files: set[str] | None,
    published_versions: dict[str, str],
    rebuild_all: bool,
) -> bool:
    """Determine if a package needs to be built."""
    if rebuild_all:
        return True

    yaml_version = f"{pkg['version']}-r{pkg['epoch']}"
    published = published_versions.get(name, "")

    # If no BASE_REF (changed_files is None), just compare versions
    if changed_files is None:
        return yaml_version != published

    # Check if any package files changed
    files_changed = any(
        any(changed.startswith(p.rstrip("*")) for p in pkg["paths"])
        for changed in changed_files
    )

    if not files_changed:
        return False

    # Check if version differs from published
    return yaml_version != published


def main() -> None:
    base_ref = os.environ.get("BASE_REF")
    repo_url = os.environ.get("REPO_URL", "https://elohmeier.github.io/alpine-packages")
    rebuild_all = os.environ.get("REBUILD_ALL", "").lower() == "true"

    local_packages = get_local_packages()
    packages = {}

    # Parse all package YAMLs
    for yaml_file in sorted(Path(".").glob("*.yaml")):
        if yaml_file.name.startswith("."):
            continue
        pkg_data = parse_yaml(yaml_file)
        name = pkg_data.get("package", {}).get("name")
        if not name:
            continue
        archs = pkg_data.get("package", {}).get("target-architecture")
        if not archs:
            print(f"Error: {yaml_file} missing target-architecture", file=sys.stderr)
            sys.exit(1)

        build_deps, runtime_deps = extract_dependencies(pkg_data, local_packages)
        packages[name] = {
            "yaml": yaml_file.name,
            "version": pkg_data["package"]["version"],
            "epoch": pkg_data["package"]["epoch"],
            "architectures": archs,
            # All local deps (for phase ordering and artifact downloads)
            "local_dependencies": sorted(set(build_deps + runtime_deps)),
            # Only build-time deps (for rebuild propagation)
            "build_dependencies": build_deps,
            "paths": [yaml_file.name] + ([f"{name}/**"] if Path(name).is_dir() else []),
        }

    # Determine what needs building
    changed_files = get_changed_files(base_ref)
    published_versions = get_published_versions(repo_url)

    needs_build = set()
    for name, pkg in packages.items():
        if package_needs_build(name, pkg, changed_files, published_versions, rebuild_all):
            needs_build.add(name)

    # Dependency propagation: only rebuild if a BUILD-TIME dep rebuilds
    # Runtime deps don't affect the package contents, just the install requirements
    changed = True
    while changed:
        changed = False
        for name, pkg in packages.items():
            if name not in needs_build:
                if any(dep in needs_build for dep in pkg["build_dependencies"]):
                    needs_build.add(name)
                    changed = True

    # Filter to only packages that need building
    filtered = {k: v for k, v in packages.items() if k in needs_build}
    # Packages that don't need building are considered already built
    already_built = set(packages.keys()) - needs_build
    phases = compute_phases(filtered, already_built) if filtered else []

    # Expand phases into matrix entries: [{package, arch, runner}, ...]
    arch_to_runner = {
        "x86_64": "ubuntu-latest",
        "aarch64": "ubuntu-24.04-arm",
        "armhf": "ubuntu-24.04-arm",
    }
    expanded_phases = []
    for phase in phases:
        entries = []
        for pkg_name in phase:
            for arch in filtered[pkg_name]["architectures"]:
                entries.append({
                    "package": pkg_name,
                    "arch": arch,
                    "runner": arch_to_runner.get(arch, "ubuntu-latest"),
                })
        expanded_phases.append(entries)

    # Output in GitHub Actions format
    print(f"packages={json.dumps(filtered)}")
    print(f"phases={json.dumps(expanded_phases)}")
    print(f"any-builds={'true' if filtered else 'false'}")
