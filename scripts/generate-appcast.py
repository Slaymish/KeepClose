#!/usr/bin/env python3
"""Keep Close release metadata; shared appcast implementation lives in HamishNativeLibrary."""
from pathlib import Path
import subprocess
import sys
sys.exit(subprocess.call([str(Path(__file__).with_name('native-library-tool')), 'appcast.py',
    '--repo', 'slaymish/KeepClose', '--title', 'Keep Close', '--minimum-system-version', '14.0', *sys.argv[1:]]))
