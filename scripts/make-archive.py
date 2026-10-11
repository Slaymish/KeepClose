#!/usr/bin/env python3
"""Zip a macOS .app bundle or a single binary, then verify the archive contents.

Used by scripts/build-selfsigned.sh because ditto(1) archives of the app bundle
have produced archives missing Contents/MacOS on this machine.
"""
import argparse
from datetime import datetime
from pathlib import Path
import stat
import sys
import zipfile


def add(zf: zipfile.ZipFile, path: Path, root: Path) -> None:
    """Add one entry, preserving Unix permissions and symlinks as symlinks."""
    relative = path.relative_to(root)
    arcname = root.name if relative == Path('.') else f'{root.name}/{relative}'
    info = zipfile.ZipInfo(arcname + ('/' if path.is_dir() else ''))
    info.date_time = datetime.fromtimestamp(path.lstat().st_mtime).timetuple()[:6]
    mode = path.lstat().st_mode
    info.external_attr = (stat.S_IMODE(mode) & 0xFFFF) << 16
    if path.is_symlink():
        info.external_attr |= 0xA000 << 16
        zf.writestr(info, str(path.readlink()).encode())
    elif path.is_dir():
        info.external_attr |= 0x10
        zf.writestr(info, b'')
    else:
        info.compress_type = zipfile.ZIP_DEFLATED
        with path.open('rb') as stream:
            zf.writestr(info, stream.read())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--expect', required=True, help='relative path that must exist in the archive')
    args = parser.parse_args()
    source = args.source.resolve()
    if not source.exists():
        print(f'{source} does not exist', file=sys.stderr)
        return 1

    if source.is_dir():
        paths = [source] + sorted((p for p in source.rglob('*') if not p.name.startswith('._')), key=lambda p: str(p))
    else:
        paths = [source]
    with zipfile.ZipFile(args.archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for path in paths:
            add(zf, path, source)

    with zipfile.ZipFile(args.archive) as zf:
        names = zf.namelist()
        wanted = f'{source.name}/{args.expect}' if source.is_dir() else source.name
        if wanted not in names:
            print(f'{args.archive} is missing {wanted}; contains {len(names)} entries', file=sys.stderr)
            for name in names[:8]:
                print(f'  {name}', file=sys.stderr)
            return 1
        if source.is_dir() and not any(name.startswith(f'{source.name}/Contents/MacOS/') for name in names):
            print(f'{args.archive} has no app binary', file=sys.stderr)
            return 1
    print(f'{args.archive.name}: {len(names)} entries, {args.archive.stat().st_size} bytes')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
