#!/usr/bin/env python3
"""Verify branch-specific missing MG answers and type outputs on macOS."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / '.build/identity-answer-tests'


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    for scheme in ('rootless', 'roothide'):
        extra = []
        if scheme == 'roothide':
            extra = [
                '-DMKS_ROOTHIDE', '-I', ROOT / 'tests/fixtures/roothide-sdk',
                ROOT / 'tests/roothide_host.m',
            ]
        binary = BUILD / scheme
        command = [
            'xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
            '-Wno-unused-function', *extra, ROOT / 'tests/identity_answer_tests.m',
            ROOT / 'common/MKSProfile.m', '-framework', 'Foundation', '-o', binary,
        ]
        subprocess.run([str(value) for value in command], cwd=ROOT, check=True)
        subprocess.run([str(binary), str(BUILD / (scheme + '.json'))], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
