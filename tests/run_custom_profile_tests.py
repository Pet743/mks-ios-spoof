#!/usr/bin/env python3
"""Compile real profile editing/settings behavior against either source snapshot."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile

root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--source-root',type=Path,default=root)
args=parser.parse_args();source=args.source_root.resolve()
build=root/'.build/custom-profile-tests';build.mkdir(parents=True,exist_ok=True)
for scheme in ('rootless','roothide'):
    binary=build/(scheme+'-'+source.name)
    extra=['-DMKS_ROOTHIDE','-I',str(source/'tests/fixtures/roothide-sdk'),str(source/'tests/roothide_host.m')] if scheme=='roothide' else []
    command=['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-unused-parameter',*extra,
             '-I',str(source/'common'),str(root/'tests/custom_profile_tests.m'),str(source/'common/MKSProfile.m'),'-framework','Foundation','-o',str(binary)]
    subprocess.run(command,check=True)
    with tempfile.TemporaryDirectory(prefix='mks-custom-') as directory:
        result=subprocess.run([str(binary),directory,str(build/(scheme+'-html-cases.json'))])
        if result.returncode:sys.exit(result.returncode)
