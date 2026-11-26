#!/usr/bin/env python3
"""Exercise StoreKit injection selection and refresh against any source snapshot."""
import argparse
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--source-root',type=Path,default=root)
source = parser.parse_args().source_root.resolve()
spec = importlib.util.spec_from_file_location('storekit_build',source/'scripts/build.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)
filtered = plistlib.loads(build.tweak_filter('roothide'))['Filter']['Executables']
covered = 'storekitd' in filtered
rootless_preserved = build.tweak_filter('rootless') == (source/'tweak/mks.plist').read_bytes()
print(f'STOREKIT_FILTER roothide={"covered" if covered else "missing"} rootless_template={"preserved" if rootless_preserved else "changed"}',flush=True)
directory = root/'.build/storekit-coverage'/source.name
directory.mkdir(parents=True,exist_ok=True)
binary = directory/'refresh'
subprocess.run(['xcrun','clang','-Wall','-Wextra','-Werror','-DMKS_REFRESH_TEST',
                '-I',str(source/'daemon'),str(root/'tests/storekit_refresh_tests.c'),
                str(source/'daemon/MKSProcessRefresh.c'),'-o',str(binary)],check=True)
refreshed = subprocess.run([str(binary)]).returncode == 0
sys.exit(0 if covered and rootless_preserved and refreshed else 1)
