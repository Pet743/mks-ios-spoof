#!/usr/bin/env python3
from pathlib import Path, PurePosixPath
import io
import plistlib
import subprocess
import tarfile
import zipfile

ROOT=Path(__file__).resolve().parents[1]
def main():
    deb=ROOT/'dist/mks_1.12.deb';ipa=ROOT/'dist/MKS-spoofer-1.12.ipa'
    names=subprocess.check_output(['ar','-t',str(deb)],text=True).splitlines()
    assert names==['debian-binary','control.tar.xz','data.tar.xz'],names
    assert subprocess.check_output(['ar','-p',str(deb),'debian-binary'])==b'2.0\n'
    control=subprocess.check_output(['ar','-p',str(deb),'control.tar.xz'])
    with tarfile.open(fileobj=io.BytesIO(control),mode='r:xz') as t:
        installer=t.extractfile('./preinst').read()
        assert b'/var/jb/var/lib/mks' in installer and b'/var/mobile/Media/mks.config' in installer
        assert b'chmod 700 /var/jb/var/lib/mks-keychain-backups' in installer
        assert t.getmember('./preinst').mode==0o755
        assert b'Version: 1.12\n' in t.extractfile('./control').read()
    data=subprocess.check_output(['ar','-p',str(deb),'data.tar.xz'])
    with tarfile.open(fileobj=io.BytesIO(data),mode='r:xz') as t:
        members=t.getmembers()
        directories={m.name.removeprefix('./') for m in members if m.isdir()}
        seen=set()
        for member in members:
            name=member.name.removeprefix('./')
            if member.isfile():
                parents={p.as_posix() for p in PurePosixPath(name).parents if p.as_posix()!='.'}
                assert parents<=seen,('Missing parent directories before file',name,parents-seen)
            if member.isdir():
                assert member.mode==0o755
                seen.add(name)
        assert {'var/jb/Applications/MKS.app','var/jb/Library/LaunchDaemons'}<=directories
        files={m.name.removeprefix('./'):(m,t.extractfile(m).read()) for m in t.getmembers() if m.isfile()}
    checks=0
    for relative,local in [
        ('var/jb/Library/MobileSubstrate/DynamicLibraries/mks.dylib','.build/ios/mks.dylib'),
        ('var/jb/usr/libexec/mksd','.build/ios/mksd'),
        ('var/jb/Applications/MKS.app/MKS','.build/ios/MKS.app/MKS')]:
        info,blob=files[relative];assert blob==(ROOT/local).read_bytes();assert info.mode==0o755
        assert info.uid==0 and info.gid==0
        arch=subprocess.check_output(['lipo','-archs',str(ROOT/local)],text=True).strip()
        assert arch=='arm64 arm64e',arch
        subprocess.run(['codesign','--verify','--strict',str(ROOT/local)],check=True,capture_output=True)
        checks+=1
    plist=plistlib.loads(files['var/jb/Library/MobileSubstrate/DynamicLibraries/mks.plist'][1])
    assert {'adid','CommCenter','SpringBoard','lockdownd','amsaccountsd'}<=set(plist['Filter']['Executables'])
    with zipfile.ZipFile(ipa) as z:
        assert z.testzip() is None
        for name in z.namelist():
            local='var/jb/Applications/MKS.app/'+name.removeprefix('Payload/MKS.app/')
            assert z.read(name)==files[local][1],name
        info=plistlib.loads(z.read('Payload/MKS.app/Info.plist'))
        assert info['CFBundleShortVersionString']=='1.12'
        assert info['CFBundleIdentifier']=='com.mks.spoofer'
    print(f'PACKAGE binaries={checks} failures=0; deb/IPA payloads, arm64+arm64e, signatures, modes and filter verified')
if __name__=='__main__':main()
