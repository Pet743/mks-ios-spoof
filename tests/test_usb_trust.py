#!/usr/bin/env python3
"""Verify USB process exclusion while retaining store/auth injection and refresh."""
import argparse
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import sys

root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--source-root',type=Path,default=root)
source=parser.parse_args().source_root.resolve()
spec=importlib.util.spec_from_file_location('usb_build',source/'scripts/build.py')
build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)
rootless=build.tweak_filter('rootless')==(source/'tweak/mks.plist').read_bytes()
executables=plistlib.loads(build.tweak_filter('roothide'))['Filter']['Executables']
excluded='lockdownd' not in executables
commerce={'accountsd','akd','appstored','itunesstored','storekitd'}<=set(executables)
print(f'USB_FILTER lockdownd={"excluded" if excluded else "injected"} commerce={"retained" if commerce else "missing"} rootless_template={"preserved" if rootless else "changed"}',flush=True)
failed=not(excluded and commerce and rootless)
directory=root/'.build/usb-trust-tests'/source.name;directory.mkdir(parents=True,exist_ok=True)
for scheme in ('rootless','roothide'):
    binary=directory/scheme
    extra=['-DMKS_ROOTHIDE'] if scheme=='roothide' else []
    command=['xcrun','clang','-Wall','-Wextra','-Werror','-Wno-unused-function','-DMKS_REFRESH_TEST',*extra,
             '-I',str(source/'common'),'-I',str(source/'daemon'),str(root/'tests/usb_trust_tests.c'),
             str(source/'daemon/MKSProcessRefresh.c'),'-o',str(binary)]
    subprocess.run(command,check=True)
    failed|=subprocess.run([str(binary)]).returncode!=0
sys.exit(1 if failed else 0)
