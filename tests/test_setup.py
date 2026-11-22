#!/usr/bin/env python3
"""Exercise CLI, local App socket and HTTP routing against disposable state."""
from pathlib import Path
import concurrent.futures
import fcntl
import http.client
import json
import os
import select
import socket
import subprocess
import tempfile
import time
from test_http import ROOT, build_server, DEVICE, TOKEN

OTHER='11111111-1111111111111111'
THIRD='22222222-2222222222222222'


def main():
    checks=0
    def check(condition):
        nonlocal checks
        assert condition
        checks+=1
    production_cli=ROOT/'.build/setup-cli-production'
    subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror',str(ROOT/'tests/setup_cli_host.m'),
                    str(ROOT/'daemon/MKSSetup.m'),str(ROOT/'common/MKSHTTP.m'),'-framework','Foundation',
                    '-o',str(production_cli)],check=True)
    if os.geteuid()!=0:
        denied=subprocess.run([str(production_cli),DEVICE],capture_output=True,text=True,check=False)
        check(denied.returncode==1 and json.loads(denied.stdout)['error']=='permission_denied')
    for scheme in ('rootless','roothide'):
        binary=build_server(scheme)
        with tempfile.TemporaryDirectory(prefix='mks-setup-') as directory:
            root=Path(directory);state=root/'state';state.mkdir(mode=0o750)
            socket_path=str(root/'local.sock')
            env=dict(os.environ,MKS_TEST_STATE=str(state),MKS_TEST_SETUP_UID='0',MKS_TEST_JBROOT=str(root/'jbroot'),
                     MKS_TEST_CONFIG=str(root/'profile.json'),MKS_TEST_SOCKET=socket_path,MKS_TEST_APP_PATH=str(binary))
            (state/'token').write_text(TOKEN)
            (state/'jobs.json').write_text('[]')
            def command(*args,environment=env):
                result=subprocess.run([str(binary),*args],env=environment,text=True,capture_output=True,timeout=5)
                return result.returncode,json.loads(result.stdout)
            code,result=command('--set-device-id',DEVICE,environment=dict(env,MKS_TEST_SETUP_UID='501'))
            check(code==1 and result['error']=='permission_denied' and not (state/'device-id').exists())
            for invalid in ('',DEVICE+'/../x','g'*40,'a'*39,'a'*41,DEVICE+'\nextra'):
                code,result=command('--set-device-id',invalid)
                check(code==2 and result['error']=='invalid_device_id' and not (state/'device-id').exists())
            http_process=subprocess.Popen([str(binary),str(state),TOKEN],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            local=None
            try:
                assert select.select([http_process.stdout],[],[],5)[0]
                line=http_process.stdout.readline();assert line.startswith('PORT='),(line,http_process.stderr.read())
                port=int(line.split('=')[1])
                def status(device=DEVICE,token=TOKEN):
                    connection=http.client.HTTPConnection('127.0.0.1',port,timeout=3)
                    connection.request('GET',f'/v1/devices/{device}/status',headers={'Authorization':'Bearer '+token})
                    response=connection.getresponse();body=json.loads(response.read());connection.close()
                    return response.status,body
                check(status()[0]==503 and status()[1]['requiresLocalSetup'])
                check(status(token='old-token')[0]==401)
                def local_server(expected):
                    nonlocal local
                    Path(socket_path).unlink(missing_ok=True)
                    local=subprocess.Popen([str(binary),'--local-server'],env=dict(env,MKS_TEST_APP_PATH=expected),
                                           stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
                    for _ in range(100):
                        if Path(socket_path).exists():return
                        if local.poll() is not None:raise AssertionError(local.stderr.read())
                        time.sleep(.02)
                    raise AssertionError('local socket did not start')
                local_server(str(root/'other-app'))
                check(command('--local-status')[1]['stage']=='unauthorized')
                check(command('--local-bind',DEVICE,'null')[1]['error']=='unauthorized')
                check(not (state/'device-id').exists())
                local.terminate();local.wait(timeout=3)
                local_server(str(binary))
                code,result=command('--local-status')
                assert code==0 and not result['deviceConfigured'] and result['deviceId'] is None,(code,result,local.poll(),local.stderr.read() if local.poll() is not None else '')
                checks+=1
                installation=result['installationId']
                check(len(installation)==36 and result['environment']['jailbreak']==scheme)
                code,result=command('--local-bind',DEVICE,'null')
                check(code==0 and result['configured'] and result['status']['deviceId']==DEVICE)
                check(status()[0]==200 and status()[1]['deviceId']==DEVICE)
                check((state/'device-id').stat().st_mode&0o777==0o640)
                check(command('--local-bind',OTHER,'null')[1]['error']=='device_id_changed')
                check(status()[1]['deviceId']==DEVICE)
                code,result=command('--set-device-id','ab'*20)
                check(code==0 and result=={'ok':True,'configured':True,'deviceId':'AB'*20,'outcomeUnknown':False})
                check(status(device='AB'*20)[0]==200 and status()[0]==404)
                # CLI and App compare-and-set share the same lock and readback.
                code,result=command('--local-bind',DEVICE,'AB'*20)
                check(code==0)
                with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                    attempts=list(pool.map(lambda new:command('--bind',json.dumps({'action':'bindDevice','deviceId':new,'expectedDeviceId':DEVICE})),(OTHER,THIRD)))
                check(sum(code==0 for code,_ in attempts)==1)
                check(any(result.get('error') in ('device_id_changed','resource_busy') for code,result in attempts if code))
                current=(state/'device-id').read_text()
                with (state/'setup.lock').open('w') as lock:
                    fcntl.flock(lock,fcntl.LOCK_EX)
                    code,result=command('--set-device-id',DEVICE)
                    check(code==5 and result['error']=='resource_busy' and result['retryable'])
                check((state/'device-id').read_text()==current)
                # Fixed schema rejects paths and shell requests before reaching persistence.
                for body in ({'action':'shell','deviceId':DEVICE,'expectedDeviceId':current},
                             {'action':'bindDevice','deviceId':DEVICE,'expectedDeviceId':current,'path':'/tmp/x'},
                             {'action':'bindDevice','deviceId':DEVICE,'expectedDeviceId':1}):
                    check(command('--bind',json.dumps(body))[1]['error']=='invalid_request')
                check((state/'token').read_text()==TOKEN and (state/'jobs.json').read_text()=='[]')
                check(command('--local-status')[1]['installationId']==installation)
                # Failed persistence retains the previous state.
                (state/'device-id').unlink();(state/'device-id').mkdir()
                code,result=command('--set-device-id',DEVICE)
                check(code!=0 and result['error']=='device_id_state_invalid')
                (state/'device-id').rmdir()
                state.chmod(0o777)
                check(command('--set-device-id',DEVICE)[1]['error']=='state_directory_unavailable')
                state.chmod(0o750)
                (state/'device-id').write_text(DEVICE)
                # A connection from an arbitrary program never reaches the binding parser.
                with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as client:
                    client.connect(socket_path);client.sendall(b'{"action":"shell","command":"id"}');client.shutdown(socket.SHUT_WR)
                    check(json.loads(client.recv(16384))['error']=='unauthorized')
            finally:
                for process in (http_process,local):
                    if process and process.poll() is None:process.terminate();process.wait(timeout=3)
        print(f'SETUP {scheme} CLI, App IPC, HTTP rebinding and state preservation passed')
    print(f'SETUP checks={checks} failures=0; permissions, input, atomic binding, stale confirmation and caller checks verified')


if __name__=='__main__':main()
