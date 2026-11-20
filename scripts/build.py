#!/usr/bin/env python3
"""Reproducible arm64/arm64e iOS build and rootless Debian packaging."""
from pathlib import Path, PurePosixPath
import argparse
import io
import os
import plistlib
import shutil
import subprocess
import tarfile
import zipfile

ROOT=Path(__file__).resolve().parents[1]
def run(args): subprocess.run([str(x) for x in args],cwd=ROOT,check=True)
def tar_bytes(files):
    buf=io.BytesIO()
    with tarfile.open(fileobj=buf,mode='w:xz',format=tarfile.USTAR_FORMAT) as archive:
        directories={parent.as_posix() for name,_,_ in files
                     for parent in PurePosixPath(name).parents if parent.as_posix()!='.'}
        # dpkg requires directory members before files on a clean installation.
        for name in sorted(directories,key=lambda value:(value.count('/'),value)):
            info=tarfile.TarInfo('./'+name)
            info.type=tarfile.DIRTYPE;info.mode=0o755
            info.uid=0;info.gid=0;info.uname='root';info.gname='wheel';info.mtime=0
            archive.addfile(info)
        for name,data,mode in sorted(files):
            info=tarfile.TarInfo('./'+name);info.size=len(data);info.mode=mode
            info.uid=0;info.gid=0;info.uname='root';info.gname='wheel';info.mtime=0
            archive.addfile(info,io.BytesIO(data))
    return buf.getvalue()
def ar_write(path,members):
    with path.open('wb') as stream:
        stream.write(b'!<arch>\n')
        for name,data in members:
            stream.write(f'{name:<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(data):<10}`\n'.encode())
            stream.write(data)
            if len(data)%2:stream.write(b'\n')
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--simulator',action='store_true');args=parser.parse_args()
    build=ROOT/'.build'/('simulator' if args.simulator else 'ios');build.mkdir(parents=True,exist_ok=True)
    sdk='iphonesimulator' if args.simulator else 'iphoneos'
    sdk_path=subprocess.check_output(['xcrun','--sdk',sdk,'--show-sdk-path'],text=True).strip()
    flags=['xcrun','--sdk',sdk,'clang','-isysroot',sdk_path,'-O2','-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-unused-parameter']
    if args.simulator: flags+=['-target','arm64-apple-ios14.0-simulator']
    else: flags+=['-arch','arm64','-arch','arm64e','-miphoneos-version-min=14.0']
    app=build/'MKS.app';app.mkdir(exist_ok=True)
    run(flags+['app/main.m','app/MKSAPIDocsController.m','common/MKSHTTP.m','common/MKSProfile.m','common/MKSKeychainIPC.m','-framework','UIKit','-framework','Foundation','-o',app/'MKS'])
    info=plistlib.loads((ROOT/'app/Info.plist').read_bytes())
    if args.simulator:info['CFBundleSupportedPlatforms']=['iPhoneSimulator']
    (app/'Info.plist').write_bytes(plistlib.dumps(info))
    if args.simulator:
        run(['codesign','-f','-s','-',app]);print('SIMULATOR_APP',app);return
    run(flags+['-dynamiclib','tweak/mks.m','common/MKSProfile.m','-framework','Foundation',
               '-Wl,-install_name,/var/jb/Library/MobileSubstrate/DynamicLibraries/mks.dylib','-o',build/'mks.dylib'])
    # Compile C without ARC, then link the status adapter and shared parser as Objective-C.
    cflags=[x for x in flags if x!='-fobjc-arc']
    run(cflags+['-c','daemon/mksd.c','-o',build/'mksd.o'])
    run(flags+[build/'mksd.o','daemon/MKSStatus.m','daemon/MKSKeychainService.m','daemon/MKSOperations.m','daemon/MKSHTTPServer.m','common/MKSHTTP.m','common/MKSProfile.m','common/MKSKeychain.m','common/MKSKeychainIPC.m','-framework','Foundation','-lsqlite3','-o',build/'mksd'])
    app_entitlements=build/'app-entitlements.plist'
    app_entitlements.write_bytes(plistlib.dumps({'platform-application':True,'com.apple.private.security.no-sandbox':True}))
    run(['codesign','-f','-s','-','--entitlements',app_entitlements,app])
    run(['codesign','-f','-s','-',build/'mks.dylib'])
    run(['codesign','-f','-s','-',build/'mksd'])
    for binary in [app/'MKS',build/'mks.dylib',build/'mksd']:run(['codesign','--verify','--strict',binary])
    dist=ROOT/'dist';dist.mkdir(exist_ok=True)
    with zipfile.ZipFile(dist/'MKS-spoofer-1.11.ipa','w',compression=zipfile.ZIP_DEFLATED) as z:
        for p in sorted(app.rglob('*')):
            if p.is_file():z.write(p,'Payload/MKS.app/'+p.relative_to(app).as_posix())
    files=[]
    for p in sorted(app.rglob('*')):
        if p.is_file(): files.append(('var/jb/Applications/MKS.app/'+p.relative_to(app).as_posix(),p.read_bytes(),0o755 if p.name=='MKS' else 0o644))
    files += [
        ('var/jb/Library/MobileSubstrate/DynamicLibraries/mks.dylib',(build/'mks.dylib').read_bytes(),0o755),
        ('var/jb/Library/MobileSubstrate/DynamicLibraries/mks.plist',(ROOT/'tweak/mks.plist').read_bytes(),0o644),
        ('var/jb/usr/libexec/mksd',(build/'mksd').read_bytes(),0o755),
        ('var/jb/Library/LaunchDaemons/com.mks.daemon.plist',(ROOT/'daemon/com.mks.daemon.plist').read_bytes(),0o644)]
    control='''Package: com.mks.spoof
Name: MKS 改机
Version: 1.11
Architecture: iphoneos-arm64
Description: Typed device profile hooks, rootless app and local daemon
Maintainer: mks
Author: mks
Section: Tweaks
Depends: firmware (>= 14.0), ellekit
'''
    preinst='''#!/bin/sh
set -e
export PATH=/var/jb/usr/bin:/var/jb/usr/sbin:/var/jb/bin:/var/jb/sbin:/usr/bin:/bin:/usr/sbin:/sbin
mkdir -p /var/jb/var/run
mkdir -p /var/jb/var/lib/mks-http
chown root:mobile /var/jb/var/lib/mks-http
chmod 750 /var/jb/var/lib/mks-http
mkdir -p /var/jb/var/lib/mks-keychain-backups
chown root:wheel /var/jb/var/lib/mks-keychain-backups
chmod 700 /var/jb/var/lib/mks-keychain-backups
directory=/var/jb/var/lib/mks
profile=$directory/mks.config
mkdir -p "$directory"
chown mobile:mobile "$directory"
chmod 755 "$directory"
# Preserve an existing authoritative record, including disabled or invalid state.
if [ ! -e "$profile" ]; then
    if [ -f /var/mobile/Media/mks.config ]; then
        cp -p /var/mobile/Media/mks.config "$profile.new"
    else
        printf '%s\\n' '{"schemaVersion":2,"enabled":false,"name":"已停用","values":{}}' > "$profile.new"
    fi
    chown mobile:mobile "$profile.new"
    chmod 644 "$profile.new"
    mv -f "$profile.new" "$profile"
fi
chown mobile:mobile "$profile"
chmod 644 "$profile"
'''
    postinst='''#!/bin/sh
set -e
export PATH=/var/jb/usr/bin:/var/jb/usr/sbin:/var/jb/bin:/var/jb/sbin:/usr/bin:/bin:/usr/sbin:/sbin
launchctl unload /var/jb/Library/LaunchDaemons/com.mks.daemon.plist 2>/dev/null || true
launchctl load /var/jb/Library/LaunchDaemons/com.mks.daemon.plist
uicache -p /var/jb/Applications/MKS.app
echo 'MKS 1.11 installed. Restart target processes to load the new library.'
'''
    prerm='''#!/bin/sh
launchctl unload /var/jb/Library/LaunchDaemons/com.mks.daemon.plist 2>/dev/null || true
exit 0
'''
    postrm='''#!/bin/sh
uicache -a 2>/dev/null || true
exit 0
'''
    ar_write(dist/'mks_1.11.deb',[('debian-binary',b'2.0\n'),
        ('control.tar.xz',tar_bytes([('control',control.encode(),0o644),('preinst',preinst.encode(),0o755),('postinst',postinst.encode(),0o755),('prerm',prerm.encode(),0o755),('postrm',postrm.encode(),0o755)])),
        ('data.tar.xz',tar_bytes(files))])
    print('BUILT dist/mks_1.11.deb dist/MKS-spoofer-1.11.ipa (arm64 arm64e); signature verification passed')
if __name__=='__main__':main()
