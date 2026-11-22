#!/usr/bin/env python3
"""Production HTTP server/operations against temp profiles and fake Keychain DB.
Only MKSRespring is replaced with a file append; no real system action occurs.
"""
from pathlib import Path
import argparse
import concurrent.futures
import http.client
import json
import os
import select
import socket
import sqlite3
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]
TOKEN='0'*64
DEVICE='00000000-0000000000000000'
PREFIX='/v1/devices/'+DEVICE

def build_server(scheme):
    build=ROOT/'.build/http-tests'/scheme;build.mkdir(parents=True,exist_ok=True)
    extra=[]
    if scheme=='roothide':
        extra=['-DMKS_ROOTHIDE','-I',str(ROOT/'tests/fixtures/roothide-sdk'),str(ROOT/'tests/roothide_host.m')]
    binary=build/'http-server'
    subprocess.run(['xcrun','clang','-fobjc-arc','-DMKS_HTTP_TEST','-Wall','-Wextra','-Werror',
        str(ROOT/'tests/http_host.m'),str(ROOT/'daemon/MKSHTTPServer.m'),str(ROOT/'daemon/MKSOperations.m'),str(ROOT/'daemon/MKSSetup.m'),
        str(ROOT/'common/MKSHTTP.m'),str(ROOT/'common/MKSProfile.m'),str(ROOT/'common/MKSKeychain.m'),str(ROOT/'common/MKSKeychainIPC.m'),
        str(ROOT/'daemon/MKSKeychainService.m'),*extra,'-framework','Foundation','-lsqlite3','-o',str(binary)],check=True)
    return binary

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--scheme',choices=['rootless','roothide'],default='rootless')
    scheme=parser.parse_args().scheme
    binary=build_server(scheme)
    checks=0
    def check(test):
        nonlocal checks
        assert test
        checks+=1
    with tempfile.TemporaryDirectory(prefix='mks-http-') as directory:
        root=Path(directory);state=root/'state';state.mkdir(mode=0o750)
        db=sqlite3.connect(root/'keychain.sqlite')
        for table in ['genp','cert','keys','inet']:
            db.execute(f'CREATE TABLE {table}(id INTEGER PRIMARY KEY AUTOINCREMENT,agrp TEXT)')
            db.execute(f"INSERT INTO {table}(agrp) VALUES ('demo')")
        db.commit();db.close()
        env=dict(os.environ,MKS_TEST_STATE=str(state),MKS_TEST_JBROOT=str(root/'jbroot'),MKS_TEST_CONFIG=str(root/'profile.json'),MKS_TEST_KEYCHAIN=str(root/'keychain.sqlite'),
            MKS_TEST_BACKUPS=str(root/'backups'),MKS_TEST_RESPRING=str(root/'resprings'))
        def start(environment=env):
            p=subprocess.Popen([str(binary),str(state),TOKEN],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=environment)
            ready=select.select([p.stdout],[],[],5)[0]
            assert ready,'HTTP listener failed to start'
            line=p.stdout.readline();assert line.startswith('PORT='),(line,p.stderr.read())
            return p,int(line.split('=')[1])
        (state/'device-id').write_text(DEVICE)
        process,port=start()
        def request(method,path,body=None,key=None,headers=None):
            h={'Authorization':'Bearer '+TOKEN}
            if body is not None:h['Content-Type']='application/json'
            if key is not None:h['Idempotency-Key']=key
            if headers:h.update(headers)
            c=http.client.HTTPConnection('127.0.0.1',port,timeout=5)
            payload=json.dumps(body) if body is not None else None
            path=path.replace('/v1/',PREFIX+'/',1)
            c.request(method,path,payload,h);r=c.getresponse();data=json.loads(r.read());c.close()
            return r.status,data
        def done(job):
            for _ in range(100):
                status,result=request('GET','/v1/jobs/'+job['jobId']);assert status==200
                if result['state'] not in ['queued','running']:return result
                time.sleep(.03)
            raise AssertionError('job timeout')
        def raw(payload):
            with socket.create_connection(('127.0.0.1',port),timeout=5) as s:
                payload=payload.replace(b'/v1/',(PREFIX+'/').encode(),1)
                s.sendall(payload);s.shutdown(socket.SHUT_WR);data=b''
                while True:
                    chunk=s.recv(4096)
                    if not chunk:break
                    data+=chunk
            return int(data.split(b' ')[1])
        try:
            initial=request('GET','/v1/status');check(initial[1]['profileValid'] is False and initial[1]['deviceId']==DEVICE)
            status=initial[1]
            check(status['apiVersion']==1 and status['deviceConfigured'] is True and status['version']=='1.15.3')
            check(status['environment']=={'jailbreak':scheme,'layoutVersion':1})
            check(status['capabilities']=={'spoof':True,'restore':True,'keychainClean':True})
            installation=status['installationId'];check(len(installation)==36)
            check(TOKEN not in json.dumps(status))
            check(request('GET','/other-device')[0]==404)
            check(request('GET','/v1/status',headers={'Authorization':'Bearer wrong'})[0]==401)
            check(request('GET','/v1/status',headers={'Authorization':'Bearer wrong'})[1]['error']=='unauthorized')
            (state/'device-id').unlink()
            missing=request('GET','/v1/status')
            check(missing[0]==503 and missing[1]['error']=='device_id_not_configured' and missing[1]['requiresLocalSetup'] and not missing[1]['retryable'])
            check(request('POST','/v1/spoof',{},'unbound')[0]==503 and not (root/'resprings').exists())
            check(request('GET','/v1/status',headers={'Authorization':'Bearer wrong'})[0]==401)
            (state/'device-id').write_text(DEVICE)
            check(request('POST','/v1/spoof',{},'blocked',{'Origin':'http://example.test'})[0]==403)
            check(request('GET','/v1/spoof')[0]==405)
            check(request('POST','/v1/spoof',{})[0]==400)
            check(request('POST','/v1/restore',{'extra':True},'bad-body')[0]==400)
            check(request('POST','/v1/keychain/clean',{},'bad-confirm')[0]==400)
            check(request('POST','/v1/keychain/clean',{'confirm':1},'bad-confirm')[0]==400)
            check(request('POST','/v1/keychain/clean',{'x':True},'bad-confirm')[0]==400)
            check(request('GET','/v1/jobs/missing')[0]==404)
            check(request('POST','/v1/restore',{},'bad key')[0]==400)
            # Duplicate authorization and length, chunked framing, oversized body.
            base=('Authorization: Bearer '+TOKEN+'\r\n').encode()
            check(raw(b'GET /v1/status HTTP/1.1\r\n'+base+base+b'\r\n')==400)
            check(raw(b'POST /v1/spoof HTTP/1.1\r\n'+base+b'Content-Length: 999999\r\n\r\n')==413)
            check(raw(b'POST /v1/spoof HTTP/1.1\r\n'+base+b'Transfer-Encoding: chunked\r\n\r\n')==400)
            check(raw(b'GET /v1/status HTTP/1.1\r\n'+base+b'Content-Length: 0\r\nContent-Length: 0\r\n\r\n')==400)
            check(raw(b'POST /v1/spoof HTTP/1.1\r\n'+base+b'Content-Length: 5\r\n\r\n{}')==400)
            status,job=request('POST','/v1/spoof',{},'create-1');check(status==202 and job['state']=='queued')
            # Several concurrent identical POSTs must return exactly one job.
            with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
                retries=list(pool.map(lambda _:request('POST','/v1/spoof',{},'create-1'),range(5)))
            check(all(s==202 and j['jobId']==job['jobId'] for s,j in retries))
            result=done(job);check(result['state']=='succeeded' and result['result']['profileSaved'])
            profile=json.loads((root/'profile.json').read_text());check(profile['enabled'] is True)
            check((root/'resprings').read_text()=='respring\n')
            check(request('POST','/v1/restore',{},'create-1')[0]==409)
            status,restore=request('POST','/v1/restore',{},'restore-1');check(status==202)
            check(done(restore)['state']=='succeeded')
            check(json.loads((root/'profile.json').read_text())['enabled'] is False)
            check((root/'resprings').read_text().count('respring')==2)
            status,clean=request('POST','/v1/keychain/clean',{'confirm':True},'clean-1');check(status==202)
            result=done(clean);check(result['state']=='succeeded' and result['result']['committed'])
            check(sum(result['result']['deleted'].values())==4 and Path(result['result']['backup']).exists())
            receipt=result['result']
            check(receipt['backupCreated'] is True and receipt['backupFormatVersion']==1 and receipt['backupId']==Path(receipt['backup']).stem)
            check(not receipt['outcomeUnknown'])
            check((root/'resprings').read_text().count('respring')==2)
            check((state/'jobs.json').stat().st_mode&0o777==0o600)
            process.terminate();process.wait(timeout=3)
            process,port=start()
            s,same=request('POST','/v1/spoof',{},'create-1');check(s==202 and same['jobId']==job['jobId'])
            check(request('GET','/v1/status')[1]['installationId']==installation)
            check((state/'device-id').read_text()==DEVICE)
            time.sleep(.6);check((root/'resprings').read_text().count('respring')==2)
            # Simulate a persisted in-flight job across daemon restart: no replay.
            process.terminate();process.wait(timeout=3)
            saved=json.loads((state/'jobs.json').read_text());saved[0]['state']='running'
            (state/'jobs.json').write_text(json.dumps(saved))
            process,port=start()
            check(request('GET','/v1/jobs/'+job['jobId'])[1]['state']=='interrupted')
            check((root/'resprings').read_text().count('respring')==2)
            process.terminate();process.wait(timeout=3)
            process,port=start(dict(env,MKS_TEST_RESPRING_FAIL='1'))
            _,job=request('POST','/v1/restore',{},'restart-fails')
            result=done(job);check(result['state']=='failed' and result['result']['profileSaved'])
            check(result['result']['respringCommandSucceeded'] is False)
            check(result['result']['error']=='respring_failed' and not result['result']['retryable'])
            # Disconnect after sending a POST, then recover its job with the same key.
            before_lost=(root/'resprings').read_text().count('respring')
            payload=(f'POST {PREFIX}/restore HTTP/1.1\r\nAuthorization: Bearer {TOKEN}\r\n'
                     'Idempotency-Key: lost-reply\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}').encode()
            with socket.create_connection(('127.0.0.1',port),timeout=3) as disconnected:
                disconnected.sendall(payload)
            status,recovered=request('POST','/v1/restore',{},'lost-reply')
            check(status==202 and done(recovered)['state']=='failed')
            check(request('POST','/v1/restore',{},'lost-reply')[1]['jobId']==recovered['jobId'])
            check((root/'resprings').read_text().count('respring')==before_lost+1)
            # A failed write poisons submissions until restart, retaining the original key ledger.
            (state/'jobs.json').unlink();(state/'jobs.json').mkdir()
            check(request('POST','/v1/spoof',{},'disk-fails')[1]['error']=='job_save_failed')
            (state/'jobs.json').rmdir()
            check(request('POST','/v1/spoof',{},'after-disk-failure')[0]==503)
            check(request('POST','/v1/spoof',{},'create-1')[1]['jobId']==saved[0]['jobId'])
            process.terminate();process.wait(timeout=3)
            (state/'jobs.json').write_text('{broken')
            failed=subprocess.run([str(binary),str(state),TOKEN],capture_output=True,text=True,env=env,timeout=3)
            check(failed.returncode==1 and not failed.stdout)
            for invalid in ([saved[0],saved[0]], [{**saved[0],'state':'succeeded','result':None}]):
                ledger=json.dumps(invalid);(state/'jobs.json').write_text(ledger)
                failed=subprocess.run([str(binary),str(state),TOKEN],capture_output=True,text=True,env=env,timeout=3)
                check(failed.returncode==1 and (state/'jobs.json').read_text()==ledger)
        finally:
            if process.poll() is None:process.terminate();process.wait(timeout=5)
    print(f'HTTP {scheme} checks={checks} failures=0; auth, framing, jobs, idempotency, profile/respring, synthetic cleanup and restart recovery verified')

if __name__=='__main__':main()
