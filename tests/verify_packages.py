#!/usr/bin/env python3
from pathlib import Path, PurePosixPath
import argparse
import io
import plistlib
import subprocess
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = plistlib.loads((ROOT / 'app/Info.plist').read_bytes())['CFBundleShortVersionString']
ROOTHIDE_LIBRARY = '@loader_path/.jbroot/usr/lib/libroothide.dylib'
TWEAK_DIR = 'Library/MobileSubstrate/DynamicLibraries'
LAUNCH_PLIST = 'Library/LaunchDaemons/com.mks.daemon.plist'


def ar_member(deb, name):
    return subprocess.check_output(['ar', '-p', str(deb), name])


def verify_package(scheme, architecture, prefix, ipa):
    roothide = scheme == 'roothide'
    deb = ROOT / f'dist/mks_{VERSION}_{scheme}_{architecture}.deb'
    names = subprocess.check_output(['ar', '-t', str(deb)], text=True).splitlines()
    assert names == ['debian-binary', 'control.tar.xz', 'data.tar.xz'], names
    assert ar_member(deb, 'debian-binary') == b'2.0\n'
    with tarfile.open(fileobj=io.BytesIO(ar_member(deb, 'control.tar.xz')), mode='r:xz') as archive:
        fields = dict(line.split(': ', 1) for line in archive.extractfile('./control').read().decode().splitlines())
        assert fields['Architecture'] == architecture and fields['Version'] == VERSION
        assert fields['Package'] == 'com.mks.spoof'
        dependencies = fields['Depends'].split(', ')
        assert 'ellekit' in dependencies and ('roothide' in dependencies) == roothide
        scripts = {}
        for name in ('preinst', 'postinst', 'prerm', 'postrm'):
            member = archive.getmember(f'./{name}')
            assert member.mode == 0o755
            script = archive.extractfile(member).read()
            subprocess.run(['/bin/sh', '-n'], input=script, check=True)
            scripts[name] = script.decode()
        system_root = '/rootfs' if roothide else ''
        assert f'directory={prefix}/var/lib/mks' in scripts['preinst']
        assert f'{system_root}/var/mobile/Media/mks.config' in scripts['preinst']
        assert f'chmod 700 {prefix}/var/lib/mks-keychain-backups' in scripts['preinst']
        assert f'launchctl load {prefix}/{LAUNCH_PLIST}' in scripts['postinst']
        assert f'launchctl unload {prefix}/{LAUNCH_PLIST}' in scripts['prerm']
        assert f'uicache -p {prefix}/Applications/MKS.app' in scripts['postinst']
        if roothide:
            assert all('/var/jb' not in script for script in scripts.values())

    with tarfile.open(fileobj=io.BytesIO(ar_member(deb, 'data.tar.xz')), mode='r:xz') as archive:
        directories = set()
        files = {}
        for member in archive.getmembers():
            name = member.name.removeprefix('./')
            if member.isdir():
                assert member.mode == 0o755
                directories.add(name)
                continue
            assert member.isfile(), name
            parents = {parent.as_posix() for parent in PurePosixPath(name).parents if parent.as_posix() != '.'}
            assert parents <= directories, (name, parents - directories)
            files['/' + name] = (member, archive.extractfile(member).read())
    if roothide:
        assert 'var/jb' not in directories
    launch = plistlib.loads(files[f'{prefix}/{LAUNCH_PLIST}'][1])
    assert launch['Label'] == 'com.mks.daemon'
    assert launch['Program'] == f'{prefix}/usr/libexec/mksd'
    assert launch['StandardOutPath'] == f'{system_root}/var/mobile/mksd.out'
    assert launch['StandardErrorPath'] == f'{system_root}/var/mobile/mksd.err'
    tweak = plistlib.loads(files[f'{prefix}/{TWEAK_DIR}/mks.plist'][1])
    assert {'adid', 'CommCenter', 'SpringBoard', 'lockdownd', 'amsaccountsd'} <= set(tweak['Filter']['Executables'])
    app_dir = f'{prefix}/Applications/MKS.app/'
    info = plistlib.loads(files[app_dir + 'Info.plist'][1])
    assert info['CFBundleShortVersionString'] == VERSION
    assert info['CFBundleIdentifier'] == 'com.mks.spoofer'

    binaries = {
        'mks.dylib': f'{prefix}/{TWEAK_DIR}/mks.dylib',
        'mksd': f'{prefix}/usr/libexec/mksd',
        'MKS.app/MKS': app_dir + 'MKS',
    }
    for local, packaged in binaries.items():
        binary = ROOT / '.build/ios' / scheme / local
        member, data = files[packaged]
        assert data == binary.read_bytes() and member.mode == 0o755
        assert b'MKS_TEST_' not in data and b'MKSTestSQLiteExec' not in data
        assert member.uid == 0 and member.gid == 0
        archs = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
        assert archs == ['arm64', 'arm64e'], archs
        subprocess.run(['codesign', '--verify', '--strict', str(binary)], check=True, capture_output=True)
        for arch in archs:
            links = subprocess.check_output(['otool', '-arch', arch, '-L', str(binary)], text=True)
            assert (ROOTHIDE_LIBRARY in links) == roothide, (arch, links)
            if roothide:
                assert b'/var/jb/' not in data
            if local == 'mks.dylib':
                install_name = f'@loader_path/.jbroot{packaged}' if roothide else packaged
                assert links.splitlines()[1].strip().startswith(install_name + ' '), links
    if ipa:
        with zipfile.ZipFile(ROOT / f'dist/MKS-spoofer-{VERSION}.ipa') as archive:
            assert archive.testzip() is None
            for name in archive.namelist():
                assert name.startswith('Payload/MKS.app/')
                assert archive.read(name) == files[app_dir + name.removeprefix('Payload/MKS.app/')][1]
    print(f'PACKAGE {scheme} architecture={architecture} binaries=3 failures=0; signatures, paths, linkage and scripts verified')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--scheme', choices=('rootless', 'roothide'))
    parser.add_argument('--ipa', action='store_true', help='also verify the standalone rootless IPA')
    args = parser.parse_args()
    if args.ipa and args.scheme == 'roothide':
        parser.error('--ipa requires a rootless build')
    if args.scheme != 'roothide':
        verify_package('rootless', 'iphoneos-arm64', '/var/jb', args.ipa)
    if args.scheme != 'rootless':
        verify_package('roothide', 'iphoneos-arm64e', '', False)


if __name__ == '__main__':
    main()
