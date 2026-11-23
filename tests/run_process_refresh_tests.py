#!/usr/bin/env python3
"""Verify bounded exact-name process refresh with injected process operations."""
from pathlib import Path
import subprocess

root=Path(__file__).resolve().parents[1]
build=root/'.build/process-refresh-tests'
build.mkdir(parents=True,exist_ok=True)
binary=build/'tests'
subprocess.run(['xcrun','clang','-Wall','-Wextra','-Werror','-DMKS_REFRESH_TEST',
                str(root/'tests/process_refresh_tests.c'),str(root/'daemon/MKSProcessRefresh.c'),
                '-o',str(binary)],check=True)
subprocess.run([str(binary)],check=True)
