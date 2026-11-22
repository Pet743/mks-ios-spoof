#!/usr/bin/env python3
"""Run the production cleaner against disposable SQLite fixtures only."""
from pathlib import Path
import json
import os
import sqlite3
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
BINARY=ROOT/'.build/keychain-tests/cleaner'

def fixture(path,sequence=True):
    db=sqlite3.connect(path)
    db.execute('PRAGMA journal_mode=WAL')
    auto=' AUTOINCREMENT' if sequence else ''
    for table in ['genp','cert','keys','inet']:
        db.execute(f'CREATE TABLE {table}(id INTEGER PRIMARY KEY{auto},agrp TEXT,data BLOB)')
        db.executemany(f'INSERT INTO {table}(agrp,data) VALUES(?,?)',
                       [('apple',b'system'),('lockdown-identities',b'pairing'),('demo.app',b'fixture'),(None,b'null')])
    db.execute('CREATE TABLE unrelated(value TEXT)')
    db.execute("INSERT INTO unrelated VALUES('keep')")
    db.commit()
    return db

def rows(db,table):return db.execute(f'SELECT * FROM {table} ORDER BY id').fetchall()

def main():
    BINARY.parent.mkdir(parents=True,exist_ok=True)
    object_file=BINARY.parent/'cleaner.o'
    subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror','-Dsqlite3_exec=MKSTestSQLiteExec',
        '-c',str(ROOT/'common/MKSKeychain.m'),'-o',str(object_file)],check=True)
    subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror',str(ROOT/'tests/keychain_host.m'),
        str(object_file),str(ROOT/'tests/sqlite_faults.c'),str(ROOT/'common/MKSKeychainIPC.m'),'-framework','Foundation','-lsqlite3','-o',str(BINARY)],check=True)
    checks=0
    def check(condition):
        nonlocal checks
        assert condition
        checks+=1
    def clean(path,backup,environment=None):
        p=subprocess.run([str(BINARY),str(path),str(backup)],capture_output=True,text=True,timeout=30,env=environment)
        result=json.loads(p.stdout)
        check(p.returncode==(0 if result['ok'] else 1))
        return result
    with tempfile.TemporaryDirectory(prefix='mks-keychain-fixtures-') as directory:
        root=Path(directory)
        for sequences in [True,False]:
            case=root/('with-sequences' if sequences else 'without-sequences');case.mkdir()
            path=case/'fixture.sqlite';db=fixture(path,sequences)
            before={table:rows(db,table) for table in ['genp','cert','keys','inet']}
            result=clean(path,case/'backup')
            check(result['ok'] and result['committed'])
            check(result['backupCreated'] and result['backupFormatVersion']==1)
            check(result['backupId']==Path(result['backup']).stem and not result['outcomeUnknown'])
            check(result['deleted']=={'genp':2,'cert':2,'keys':2,'inet':4})
            check([r[1] for r in rows(db,'genp')]==['apple',None])
            for table in ['cert','keys']:check([r[1] for r in rows(db,table)]==['lockdown-identities',None])
            check(rows(db,'inet')==[])
            check(db.execute('SELECT * FROM unrelated').fetchall()==[('keep',)])
            backup=Path(result['backup']);saved=sqlite3.connect(backup)
            for table in before:check(rows(saved,table)==before[table])
            check(saved.execute('PRAGMA quick_check').fetchone()==('ok',))
            check(backup.stat().st_mode&0o777==0o600)
            check(backup.parent.stat().st_mode&0o777==0o700)
            if sequences:check(db.execute('SELECT count(*) FROM sqlite_sequence').fetchone()[0]==0)
            saved.close()
            # A repeat succeeds honestly with zero deletions and a new backup.
            repeat=clean(path,case/'backup');check(sum(repeat['deleted'].values())==0)
            check(repeat['backup']!=result['backup'])
            db.close()
        # Execute the sample's literal SQL independently and compare final rows
        # against MKS, including protected groups, NULLs and sequence metadata.
        case=root/'reference-equivalence';case.mkdir()
        reference=fixture(case/'reference.sqlite')
        candidate=fixture(case/'candidate.sqlite')
        for sql in ["DELETE FROM genp WHERE agrp <> 'apple'",
                    "DELETE FROM cert WHERE agrp <> 'lockdown-identities'",
                    "DELETE FROM keys WHERE agrp <> 'lockdown-identities'",
                    "DELETE FROM inet", "DELETE FROM sqlite_sequence"]:
            reference.execute(sql)
        reference.commit()
        result=clean(case/'candidate.sqlite',case/'backup');check(result['committed'])
        for table in ['genp','cert','keys','inet','sqlite_sequence']:
            check(candidate.execute(f'SELECT * FROM {table} ORDER BY rowid').fetchall()==
                  reference.execute(f'SELECT * FROM {table} ORDER BY rowid').fetchall())
        reference.close();candidate.close()
        case=root/'rollback';case.mkdir();path=case/'fixture.sqlite';db=fixture(path)
        db.execute("CREATE TRIGGER reject_cert BEFORE DELETE ON cert BEGIN SELECT RAISE(ABORT,'fixture failure'); END")
        db.commit();before={t:rows(db,t) for t in ['genp','cert','keys','inet']}
        result=clean(path,case/'backup')
        check(not result['committed'] and result['stage']=='delete' and result['deleted']=={})
        for table in before:check(rows(db,table)==before[table])
        check(Path(result['backup']).exists());db.close()
        case=root/'commit-unknown';case.mkdir();path=case/'fixture.sqlite';db=fixture(path)
        before={table:rows(db,table) for table in ['genp','cert','keys','inet']}
        result=clean(path,case/'backup',dict(os.environ,MKS_TEST_COMMIT_FAILURE='1'))
        check(not result['committed'] and result['outcomeUnknown'] and not result['retryable'])
        check(result['error']=='cleanup_outcome_unknown' and result['backupCreated'])
        for table in before:check(rows(db,table)==before[table])
        db.close()
        case=root/'locked';case.mkdir();path=case/'fixture.sqlite';db=fixture(path)
        db.execute('BEGIN IMMEDIATE')
        result=clean(path,case/'backup');check(result['stage']=='lock' and not result['committed'])
        check(not (case/'backup').exists());db.rollback();db.close()
        case=root/'insecure-backup';case.mkdir();path=case/'fixture.sqlite';db=fixture(path)
        (case/'backup').mkdir(mode=0o755)
        result=clean(path,case/'backup');check(result['stage']=='backup' and not result['committed'])
        check(result['error']=='backup_failed' and not result['backupCreated'] and not result['outcomeUnknown'])
        check(len(rows(db,'genp'))==4);db.close()
        case=root/'unsupported';case.mkdir();path=case/'fixture.sqlite';db=sqlite3.connect(path)
        db.execute('CREATE TABLE genp(id INTEGER)');db.commit();db.close()
        result=clean(path,case/'backup');check(result['stage']=='schema' and not result['committed'])
        check(not (case/'backup').exists())
        missing=root/'missing.sqlite';result=clean(missing,root/'backup')
        check(result['stage']=='database_missing' and not missing.exists())
        link=root/'link.sqlite';link.symlink_to(path)
        result=clean(link,root/'backup');check(result['stage']=='database_missing')
        expected=root/'MKS';expected.write_text('app');other=root/'other';other.write_text('other')
        p=subprocess.run([str(BINARY),'--ipc',str(expected),str(other)],capture_output=True,text=True)
        check(p.returncode==0)
        print(p.stdout,end='')
    print(f'KEYCHAIN checks={checks} failures=0; sample SQL equivalence, WAL backup, protected groups, transaction rollback, locks, modes and IPC verified')

if __name__=='__main__':main()
