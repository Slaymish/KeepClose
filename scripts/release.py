#!/usr/bin/env python3
"""Prepare version/changelog metadata, or validate/extract it for tagged CI."""
import argparse
from datetime import date
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('command', choices=['prepare', 'verify', 'notes'])
parser.add_argument('version')
parser.add_argument('--github-output', type=Path)
parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
args = parser.parse_args()
root = args.root
if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', args.version):
    parser.error('Use a stable semantic version such as 0.2.0 (without v).')
project = root / 'project.yml'
changelog = root / 'CHANGELOG.md'
config = project.read_text()
text = changelog.read_text()
version_match = re.search(r"MARKETING_VERSION: '?([0-9.]+)'?", config)
build_match = re.search(r'CURRENT_PROJECT_VERSION: (\d+)', config)
if not version_match or not build_match:
    parser.error('Version/build settings missing from project.yml.')
section = re.search(r'^## \[' + re.escape(args.version) + r'\] - (\d{4}-\d{2}-\d{2})\n(.*?)(?=^## |\Z)', text, re.M | re.S)
if args.command == 'prepare':
    if section:
        parser.error('This version already has a changelog entry.')
    def semver(v):
        return tuple(map(int, v.split('.')))
    if semver(args.version) < semver(version_match.group(1)):
        parser.error('Version cannot go backwards.')
    existing = re.findall(r'^## \[([0-9.]+)\]', text, re.M)
    if existing and semver(args.version) <= max(map(semver, existing)):
        parser.error('Choose a version newer than the existing releases.')
    unreleased = re.search(r'^## \[Unreleased\]\n(.*?)(?=^## |\Z)', text, re.M | re.S)
    if not unreleased or not unreleased.group(1).strip():
        parser.error('Write concrete changes under [Unreleased] before preparing a release.')
    release = '## [Unreleased]\n\n## [%s] - %s\n%s' % (args.version, date.today().isoformat(), unreleased.group(1))
    text = text[:unreleased.start()] + release + text[unreleased.end():]
    config = re.sub(r"MARKETING_VERSION: '?[0-9.]+'?", "MARKETING_VERSION: '%s'" % args.version, config)
    config = re.sub(r'CURRENT_PROJECT_VERSION: \d+', 'CURRENT_PROJECT_VERSION: %d' % (int(build_match.group(1)) + 1), config)
    project.write_text(config)
    changelog.write_text(text)
    subprocess.run(['xcodegen', 'generate'], cwd=root, check=True)
    print('Prepared %s. Review changes, run checks, then commit and tag v%s.' % (args.version, args.version))
else:
    if version_match.group(1) != args.version or not section or not section.group(2).strip():
        parser.error('Tag, project version and nonempty dated changelog entry must agree.')
    if args.command == 'notes':
        print(section.group(2).strip())
    elif args.github_output:
        with args.github_output.open('a') as stream:
            stream.write('version=%s\nbuild=%s\n' % (args.version, build_match.group(1)))
    else:
        print('Release metadata valid: %s (build %s)' % (args.version, build_match.group(1)))
