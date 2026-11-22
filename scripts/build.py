#!/usr/bin/env python3
"""Build separate rootless and RootHide Debian packages for iOS."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import io
import plistlib
import subprocess
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SCHEMES = {
    'rootless': ('iphoneos-arm64', '/var/jb'),
    'roothide': ('iphoneos-arm64e', ''),
}
ROOTHIDE_SDK = {
    'roothide.h': (
        'headers', '166f8309d28d6c5c581617c538e76592c2c213ba',
        '086e3d87f45c43e705d50b5b095380d5d307fcf667e0b0259698e9b4f0dd833f',
    ),
    'libroothide.tbd': (
        'lib', 'ecf702bb0ae2aedb6d290a0f9bf369b2a65681ab',
        'f96b3b624f17dfd54ed59b05592ae3b0216adc9ac4ee2464348156ad017091c5',
    ),
}
TWEAK_DIR = '/Library/MobileSubstrate/DynamicLibraries'
DAEMON_PLIST = '/Library/LaunchDaemons/com.mks.daemon.plist'


def run(args):
    subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True)


def roothide_sdk():
    directory = ROOT / '.build/roothide-sdk'
    directory.mkdir(parents=True, exist_ok=True)
    for filename, (repo, blob, digest) in ROOTHIDE_SDK.items():
        path = directory / filename
        if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == digest:
            continue
        url = f'https://api.github.com/repos/roothide/{repo}/git/blobs/{blob}'
        data = subprocess.check_output([
            'curl', '-fsSL', '--retry', '2', '--max-time', '25',
            '-H', 'Accept: application/vnd.github.raw+json', url,
        ])
        if hashlib.sha256(data).hexdigest() != digest:
            raise RuntimeError(f'RootHide SDK checksum mismatch for {filename}')
        path.write_bytes(data)
    return directory


def tar_bytes(files):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode='w:xz', format=tarfile.USTAR_FORMAT) as archive:
        directories = {parent.as_posix() for name, _, _ in files
                       for parent in PurePosixPath(name).parents if parent.as_posix() != '.'}
        # dpkg requires directory members before files on a clean installation.
        for name in sorted(directories, key=lambda value: (value.count('/'), value)):
            info = tarfile.TarInfo('./' + name)
            info.type, info.mode = tarfile.DIRTYPE, 0o755
            info.uname, info.gname = 'root', 'wheel'
            archive.addfile(info)
        for name, data, mode in sorted(files):
            info = tarfile.TarInfo('./' + name)
            info.size, info.mode = len(data), mode
            info.uname, info.gname = 'root', 'wheel'
            archive.addfile(info, io.BytesIO(data))
    return buf.getvalue()


def ar_write(path, members):
    with path.open('wb') as stream:
        stream.write(b'!<arch>\n')
        for name, data in members:
            stream.write(f'{name:<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(data):<10}`\n'.encode())
            stream.write(data)
            if len(data) % 2:
                stream.write(b'\n')


def sdk_flags(sdk):
    sdk_path = subprocess.check_output(['xcrun', '--sdk', sdk, '--show-sdk-path'], text=True).strip()
    return ['xcrun', '--sdk', sdk, 'clang', '-isysroot', sdk_path, '-O2',
            '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter']


def build_app(build, flags, link, simulator=False):
    app = build / 'MKS.app'
    app.mkdir(parents=True, exist_ok=True)
    run(flags + ['-fobjc-arc', 'app/main.m', 'app/MKSAPIDocsController.m',
                 'common/MKSHTTP.m', 'common/MKSProfile.m', 'common/MKSKeychainIPC.m',
                 '-framework', 'UIKit', '-framework', 'Foundation', *link, '-o', app / 'MKS'])
    info = plistlib.loads((ROOT / 'app/Info.plist').read_bytes())
    if simulator:
        info['CFBundleSupportedPlatforms'] = ['iPhoneSimulator']
    (app / 'Info.plist').write_bytes(plistlib.dumps(info))
    return app, info['CFBundleShortVersionString']


def control_files(scheme, architecture, prefix, version):
    roothide = scheme == 'roothide'
    depends = 'firmware (>= 14.0), ellekit'
    if roothide:
        depends += ', roothide'
    control = f'''Package: com.mks.spoof
Name: MKS 改机
Version: {version}
Architecture: {architecture}
Description: MKS app, tweak and local daemon for {scheme}
Maintainer: mks
Author: mks
Section: Tweaks
Depends: {depends}
'''
    bootstrap_path = f'{prefix}/usr/bin:{prefix}/usr/sbin:{prefix}/bin:{prefix}/sbin'
    if not roothide:
        bootstrap_path += ':/usr/bin:/usr/sbin:/bin:/sbin'
    shell_path = f'export PATH={bootstrap_path}\n'
    legacy_profile = '/rootfs/var/mobile/Media/mks.config' if roothide else '/var/mobile/Media/mks.config'
    preinst = f'''#!/bin/sh
set -e
{shell_path}mkdir -p {prefix}/var/run
mkdir -p {prefix}/var/lib/mks-http
chown root:mobile {prefix}/var/lib/mks-http
chmod 750 {prefix}/var/lib/mks-http
mkdir -p {prefix}/var/lib/mks-keychain-backups
chown root:wheel {prefix}/var/lib/mks-keychain-backups
chmod 700 {prefix}/var/lib/mks-keychain-backups
directory={prefix}/var/lib/mks
profile=$directory/mks.config
mkdir -p "$directory"
chown mobile:mobile "$directory"
chmod 755 "$directory"
# Preserve an existing authoritative record, including disabled or invalid state.
if [ ! -e "$profile" ]; then
    if [ -f {legacy_profile} ]; then
        cp -p {legacy_profile} "$profile.new"
    else
        printf '%s\\n' '{{"schemaVersion":2,"enabled":false,"name":"已停用","values":{{}}}}' > "$profile.new"
    fi
    chown mobile:mobile "$profile.new"
    chmod 644 "$profile.new"
    mv -f "$profile.new" "$profile"
fi
chown mobile:mobile "$profile"
chmod 644 "$profile"
'''
    postinst = f'''#!/bin/sh
set -e
{shell_path}launchctl unload {prefix}{DAEMON_PLIST} 2>/dev/null || true
launchctl load {prefix}{DAEMON_PLIST}
uicache -p {prefix}/Applications/MKS.app
echo 'MKS {version} ({scheme}) installed. Restart target processes to load the new library.'
'''
    prerm = f'''#!/bin/sh
{shell_path}launchctl unload {prefix}{DAEMON_PLIST} 2>/dev/null || true
exit 0
'''
    postrm = f'''#!/bin/sh
{shell_path}uicache -a 2>/dev/null || true
exit 0
'''
    return [('control', control.encode(), 0o644)] + [
        (name, script.encode(), 0o755)
        for name, script in [('preinst', preinst), ('postinst', postinst),
                             ('prerm', prerm), ('postrm', postrm)]
    ]


def build_device(scheme, ipa):
    architecture, prefix = SCHEMES[scheme]
    roothide = scheme == 'roothide'
    build = ROOT / '.build/ios' / scheme
    flags = sdk_flags('iphoneos') + ['-arch', 'arm64', '-arch', 'arm64e', '-miphoneos-version-min=14.0']
    link = []
    if roothide:
        sdk = roothide_sdk()
        flags += ['-DMKS_ROOTHIDE', '-I', sdk]
        link = [sdk / 'libroothide.tbd']
    app, version = build_app(build, flags, link)
    install_name = f'@loader_path/.jbroot{TWEAK_DIR}/mks.dylib' if roothide else f'{prefix}{TWEAK_DIR}/mks.dylib'
    dylib = build / 'mks.dylib'
    daemon = build / 'mksd'
    run(flags + ['-fobjc-arc', '-dynamiclib', 'tweak/mks.m', 'common/MKSProfile.m',
                 '-framework', 'Foundation', *link, f'-Wl,-install_name,{install_name}', '-o', dylib])
    run(flags + ['-c', 'daemon/mksd.c', '-o', build / 'mksd.o'])
    run(flags + ['-fobjc-arc', build / 'mksd.o', 'daemon/MKSStatus.m', 'daemon/MKSKeychainService.m',
                 'daemon/MKSOperations.m', 'daemon/MKSHTTPServer.m', 'common/MKSHTTP.m',
                 'common/MKSProfile.m', 'common/MKSKeychain.m', 'common/MKSKeychainIPC.m',
                 '-framework', 'Foundation', '-lsqlite3', *link, '-o', daemon])

    entitlements = {'platform-application': True, 'com.apple.private.security.no-sandbox': True}
    if roothide:
        entitlements.update({
            'com.apple.private.security.storage.AppBundles': True,
            'com.apple.private.security.storage.AppDataContainers': True,
        })
    entitlements_file = build / 'entitlements.plist'
    entitlements_file.write_bytes(plistlib.dumps(entitlements))
    run(['codesign', '-f', '-s', '-', '--entitlements', entitlements_file, app])
    run(['codesign', '-f', '-s', '-', dylib])
    daemon_entitlements = ['--entitlements', entitlements_file] if roothide else []
    run(['codesign', '-f', '-s', '-', *daemon_entitlements, daemon])
    for binary in (app / 'MKS', dylib, daemon):
        run(['codesign', '--verify', '--strict', binary])

    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    app_files = sorted(path for path in app.rglob('*') if path.is_file())
    if ipa:
        with zipfile.ZipFile(dist / f'MKS-spoofer-{version}.ipa', 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            for path in app_files:
                archive.write(path, 'Payload/MKS.app/' + path.relative_to(app).as_posix())
    files = [
        ((prefix + '/Applications/MKS.app/' + path.relative_to(app).as_posix()).lstrip('/'),
         path.read_bytes(), 0o755 if path == app / 'MKS' else 0o644)
        for path in app_files
    ]
    launch_plist = plistlib.loads((ROOT / 'daemon/com.mks.daemon.plist').read_bytes())
    launch_plist['Program'] = f'{prefix}/usr/libexec/mksd'
    if roothide:
        for key in ('StandardOutPath', 'StandardErrorPath'):
            launch_plist[key] = '/rootfs' + launch_plist[key]
    files += [
        ((prefix + f'{TWEAK_DIR}/mks.dylib').lstrip('/'), dylib.read_bytes(), 0o755),
        ((prefix + f'{TWEAK_DIR}/mks.plist').lstrip('/'), (ROOT / 'tweak/mks.plist').read_bytes(), 0o644),
        ((prefix + '/usr/libexec/mksd').lstrip('/'), daemon.read_bytes(), 0o755),
        ((prefix + DAEMON_PLIST).lstrip('/'), plistlib.dumps(launch_plist), 0o644),
    ]
    deb = dist / f'mks_{version}_{scheme}_{architecture}.deb'
    ar_write(deb, [
        ('debian-binary', b'2.0\n'),
        ('control.tar.xz', tar_bytes(control_files(scheme, architecture, prefix, version))),
        ('data.tar.xz', tar_bytes(files)),
    ])
    print(f'BUILT dist/{deb.name} (arm64 arm64e); signature verification passed', flush=True)


def main():
    parser = argparse.ArgumentParser()
    choices = parser.add_mutually_exclusive_group()
    choices.add_argument('--scheme', choices=SCHEMES, help='build one DEB instead of both')
    choices.add_argument('--simulator', action='store_true')
    parser.add_argument('--ipa', action='store_true', help='also build the standalone rootless IPA')
    args = parser.parse_args()
    if args.ipa and (args.simulator or args.scheme == 'roothide'):
        parser.error('--ipa requires a rootless build')
    if args.simulator:
        flags = sdk_flags('iphonesimulator') + ['-target', 'arm64-apple-ios14.0-simulator']
        app, _ = build_app(ROOT / '.build/simulator', flags, [], simulator=True)
        run(['codesign', '-f', '-s', '-', app])
        print('SIMULATOR_APP', app)
        return
    for scheme in [args.scheme] if args.scheme else SCHEMES:
        build_device(scheme, args.ipa and scheme == 'rootless')


if __name__ == '__main__':
    main()
