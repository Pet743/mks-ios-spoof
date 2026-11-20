#!/usr/bin/env python3
"""Run real Objective-C regressions on macOS. No device is changed."""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'.build/host-tests'
FIXTURE=ROOT/'tests/fixtures/profile.txt'

def run(cmd):
    p=subprocess.run([str(x) for x in cmd],cwd=ROOT)
    if p.returncode: sys.exit(p.returncode)

def baseline(source):
    # Isolate the unchanged read/hook implementation from its UIKit-only hidden button.
    text=source.read_text().split('// ===================== SpringBoard')[0]
    prefix='#include <unistd.h>\n#include <signal.h>\n#include <ctype.h>\n'
    test=r'''
int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc!=2)return 2;
        NSString *s=[NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:NULL];
        split_params(s.UTF8String);
        int missing=0;
        const char *keys[]={"UniqueChipID","HWModelStr","WifiAddress","UniqueDeviceIDData","MLBSerialNumber"};
        for(int i=0;i<5;i++) {
            CFStringRef k=CFStringCreateWithCString(NULL,keys[i],kCFStringEncodingUTF8);
            if(!answer_for_key(k)) { printf("BASELINE missing=%s\n",keys[i]);missing++; }
            CFRelease(k);
        }
        CFStringRef chip=answer_for_key(CFSTR("ChipID"));
        int wrong=chip && CFGetTypeID(chip)!=CFNumberGetTypeID();
        printf("BASELINE missing_fields=%d chip_type=%s\n",missing,wrong?"CFString (expected CFNumber)":"CFNumber");
        return missing || wrong ? 1 : 0;
    }
}
'''
    path=BUILD/'baseline.m';path.write_text(prefix+text+test)
    run(['xcrun','clang','-fobjc-arc','-Wno-deprecated-declarations','-Wno-unused-function',path,'-framework','Foundation','-o',BUILD/'baseline'])
    return subprocess.run([str(BUILD/'baseline'),str(FIXTURE)]).returncode

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--baseline-source',type=Path);args=parser.parse_args()
    BUILD.mkdir(parents=True,exist_ok=True)
    if args.baseline_source: return baseline(args.baseline_source)
    run(['xcrun','clang','-fobjc-arc','-g','-O1','-Wall','-Wextra','-Werror','-Wno-unused-function',
         ROOT/'tests/host_tests.m',ROOT/'common/MKSProfile.m','-framework','Foundation','-o',BUILD/'modified'])
    return subprocess.run([str(BUILD/'modified'),str(FIXTURE),str(BUILD/'state')]).returncode

if __name__=='__main__': sys.exit(main())
