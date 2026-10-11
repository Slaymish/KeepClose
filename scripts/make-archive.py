#!/usr/bin/env python3
"""Compatibility entrypoint; archive implementation lives in HamishNativeLibrary."""
from pathlib import Path
import subprocess
import sys
sys.exit(subprocess.call([str(Path(__file__).with_name('native-library-tool')), 'make-archive.py', *sys.argv[1:]]))
