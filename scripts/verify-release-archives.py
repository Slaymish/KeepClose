#!/usr/bin/env python3
"""Verify the final app and CLI archives together before signing or publishing."""
import argparse
from pathlib import Path
import plistlib
import zipfile


def verify(folder, version, build):
    folder = Path(folder)
    app = folder / "KeepClose-macOS.zip"
    cli = folder / "keepclose-cli-macOS.zip"
    if app.name.casefold() == cli.name.casefold() or app.samefile(cli):
        raise ValueError("App and CLI archives must be separate files")
    with zipfile.ZipFile(app) as archive:
        if archive.testzip() is not None:
            raise ValueError("App archive is corrupt")
        roots = [name for name in archive.namelist() if name.endswith(".app/Contents/Info.plist") and name.count("/") == 2]
        if len(roots) != 1:
            raise ValueError("App archive must contain exactly one app bundle")
        root = roots[0].removesuffix("Contents/Info.plist")
        info = plistlib.loads(archive.read(roots[0]))
        if info.get("CFBundleShortVersionString") != version or str(info.get("CFBundleVersion")) != str(build):
            raise ValueError("App archive version/build does not match release metadata")
        executable = root + "Contents/MacOS/" + info.get("CFBundleExecutable", "")
        if not archive.read(executable):
            raise ValueError("App archive has no executable")
    with zipfile.ZipFile(cli) as archive:
        if archive.testzip() is not None or not archive.read("keepclose"):
            raise ValueError("CLI archive is incomplete or corrupt")
        if any(".app/Contents/" in name for name in archive.namelist()):
            raise ValueError("CLI archive unexpectedly contains an app")
    print("Final app and CLI archives are distinct, complete and match release metadata.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path)
    parser.add_argument("version")
    parser.add_argument("build")
    args = parser.parse_args()
    verify(args.folder, args.version, args.build)
