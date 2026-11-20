#!/usr/bin/env python3
"""Exercise the real UDP daemon and real status parser, without respring."""
import json
import os
from pathlib import Path
import socket
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'.build/daemon-tests'
def main():
    BUILD.mkdir(parents=True,exist_ok=True)
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as probe:
        probe.bind(('127.0.0.1',0));port=probe.getsockname()[1]
    subprocess.run(['xcrun','clang','-Wall','-Wextra','-Werror',f'-DAPP_PORT={port}','-c',str(ROOT/'daemon/mksd.c'),'-o',str(BUILD/'mksd.o')],check=True)
    subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror',str(BUILD/'mksd.o'),str(ROOT/'tests/daemon_host.m'),str(ROOT/'common/MKSProfile.m'),'-framework','Foundation','-o',str(BUILD/'mksd')],check=True)
    config=BUILD/'test.config';config.unlink(missing_ok=True)
    env=dict(os.environ,MKS_TEST_CONFIG=str(config))
    process=subprocess.Popen([str(BUILD/'mksd')],env=env)
    checks=0
    try:
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as client:
            client.settimeout(0.1)
            def request(data):
                client.sendto(data,('127.0.0.1',port));return client.recv(512)
            for attempt in range(30):
                try:
                    if request(b'PING')==b'PONG':break
                except socket.timeout:time.sleep(0.02)
            else:raise AssertionError('daemon not ready')
            client.settimeout(1)
            def check(data,expected):
                nonlocal checks
                result=request(data);assert result==expected,(data,result,expected);checks+=1
            check(b'PING',b'PONG');check(b'PINGextra',b'INVALID')
            # Prefix matching used to execute commands with arbitrary suffixes.
            check(b'RESPRINGextra',b'INVALID');check(b'STATUSextra',b'INVALID')
            check(b'CLEAN_KEYCHAIN_V1',b'INVALID')
            check(b'STATUS',b'MISSING_OR_INVALID')
            config.write_text(json.dumps({'schemaVersion':2,'enabled':False,'name':'off','values':{}}))
            check(b'STATUS',b'DISABLED')
            config.write_text(json.dumps({'schemaVersion':2,'enabled':True,'name':'test','values':{'SerialNumber':'DEMO'}}))
            check(b'STATUS',b'ENABLED')
            config.write_text('{invalid');check(b'STATUS',b'MISSING_OR_INVALID')
            print(f'DAEMON checks={checks} failures=0; exact commands and parsed enabled/disabled/invalid status verified')
    finally:
        process.terminate();process.wait(timeout=5);config.unlink(missing_ok=True)
if __name__=='__main__':main()
