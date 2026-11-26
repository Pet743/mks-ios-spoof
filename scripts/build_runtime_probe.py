#!/usr/bin/env python3
"""Build optional read-only process diagnostics, separately from release packages."""
import argparse
import plistlib
import re

import build


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--scheme', choices=build.SCHEMES, default='roothide')
    scheme = parser.parse_args().scheme
    root = build.ROOT
    output = root / '.build/runtime-probe' / scheme
    output.mkdir(parents=True, exist_ok=True)
    flags = build.sdk_flags('iphoneos') + [
        '-arch', 'arm64', '-arch', 'arm64e', '-miphoneos-version-min=14.0',
    ]
    link = []
    if scheme == 'roothide':
        sdk = build.roothide_sdk()
        flags += ['-DMKS_ROOTHIDE', '-I', sdk]
        link = [sdk / 'libroothide.tbd']
    # Avoid collisions with the production dylib's functions and Objective-C class.
    names = set(re.findall(r'\b(MKS[A-Za-z0-9_]+)\s*\(', (root / 'common/MKSProfile.h').read_text()))
    names.add('MKSProfileStore')
    flags += ['-D' + name + '=MV' + name for name in sorted(names)]
    library = output / 'MKSVerify.dylib'
    install_name = ('@loader_path/.jbroot' if scheme == 'roothide' else '/var/jb') + \
        '/Library/MobileSubstrate/DynamicLibraries/MKSVerify.dylib'
    build.run(flags + [
        '-fobjc-arc', '-dynamiclib', root / 'tests/runtime_probe.m',
        root / 'common/MKSProfile.m', '-framework', 'Foundation', *link,
        '-Wl,-install_name,' + install_name, '-o', library,
    ])
    build.run(['codesign', '-f', '-s', '-', library])
    build.run(['codesign', '--verify', '--strict', library])
    path = output / 'MKSVerify.plist'
    path.write_bytes(plistlib.dumps({'Filter': {'Executables': [
        'AppStore', 'akd', 'accountsd', 'amsaccountsd', 'appstored', 'itunesstored', 'storekitd',
    ]}}))
    print(f'PROBE {scheme} arm64 arm64e signature=verified')
    print(library)
    print(path)


if __name__ == '__main__':
    main()
