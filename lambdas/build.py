"""Build dist/auth.zip, the deployment package shared by both auth Lambdas.

Installs the locked dependencies as arm64 (Graviton) wheels for Python 3.12, adds src/,
and writes a byte-for-byte reproducible zip: sorted entries, fixed timestamps and
permissions, and no install metadata that varies between machines. A local build and a
CI build therefore hash the same, so `terraform plan` shows no change to the functions
unless the code or dependencies change.

Usage: python build.py
"""

import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PACKAGE = ROOT / "build" / "package"
OUTPUT = ROOT / "dist" / "auth.zip"

# Pip writes these per install; they differ between pip versions and machines.
VOLATILE = {"RECORD", "INSTALLER", "REQUESTED", "direct_url.json"}
FIXED_TIME = (1980, 1, 1, 0, 0, 0)


def install_dependencies() -> None:
    shutil.rmtree(PACKAGE, ignore_errors=True)
    subprocess.run(  # noqa: S603 - fixed arguments, no user input
        [
            sys.executable,
            "-m",
            "pip",
            "install",
            "--quiet",
            "--disable-pip-version-check",
            "--require-hashes",
            "--only-binary=:all:",
            "--platform=manylinux2014_aarch64",
            "--implementation=cp",
            "--python-version=3.12",
            "--no-compile",
            "--target",
            str(PACKAGE),
            "--requirement",
            str(ROOT / "requirements.txt"),
        ],
        check=True,
    )
    # Console scripts embed the local interpreter path and aren't needed in Lambda.
    shutil.rmtree(PACKAGE / "bin", ignore_errors=True)
    shutil.copytree(
        ROOT / "src" / "auth", PACKAGE / "auth", ignore=shutil.ignore_patterns("__pycache__")
    )


def included(path: Path) -> bool:
    return (
        path.is_file()
        and "__pycache__" not in path.parts
        and not (path.parent.name.endswith(".dist-info") and path.name in VOLATILE)
    )


def write_zip() -> None:
    OUTPUT.parent.mkdir(exist_ok=True)
    files = sorted(path for path in PACKAGE.rglob("*") if included(path))
    with zipfile.ZipFile(OUTPUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            info = zipfile.ZipInfo(path.relative_to(PACKAGE).as_posix(), FIXED_TIME)
            info.external_attr = 0o644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes(), compresslevel=9)


if __name__ == "__main__":
    install_dependencies()
    write_zip()
    print(f"{OUTPUT.relative_to(ROOT)}: {OUTPUT.stat().st_size // 1024} KiB")
