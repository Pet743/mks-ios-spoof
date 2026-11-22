#import "MKSKeychain.h"
#include <sqlite3.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

static BOOL execSQL(sqlite3 *db,const char *sql) {
    return sqlite3_exec(db,sql,NULL,NULL,NULL)==SQLITE_OK;
}
static BOOL scalar(sqlite3 *db,const char *sql,sqlite3_int64 *value) {
    sqlite3_stmt *statement=NULL;
    if(sqlite3_prepare_v2(db,sql,-1,&statement,NULL)!=SQLITE_OK) return NO;
    BOOL ok=sqlite3_step(statement)==SQLITE_ROW;
    if(ok) *value=sqlite3_column_int64(statement,0);
    sqlite3_finalize(statement);return ok;
}
static BOOL integrity(sqlite3 *db) {
    sqlite3_stmt *statement=NULL;
    if(sqlite3_prepare_v2(db,"PRAGMA quick_check(1)",-1,&statement,NULL)!=SQLITE_OK) return NO;
    BOOL ok=sqlite3_step(statement)==SQLITE_ROW &&
        !strcmp((const char *)sqlite3_column_text(statement,0),"ok");
    sqlite3_finalize(statement);return ok;
}
static int deadline(void *context) {
    return CFAbsoluteTimeGetCurrent()>*(CFAbsoluteTime *)context;
}
static BOOL saveBackup(sqlite3 *source,NSString *databasePath,NSString *backupPath) {
    int fd=open(backupPath.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if(fd<0) return NO;
    close(fd);
    sqlite3 *read=NULL,*destination=NULL;
    BOOL ok=sqlite3_open_v2(databasePath.fileSystemRepresentation,&read,SQLITE_OPEN_READONLY,NULL)==SQLITE_OK &&
        sqlite3_open_v2(backupPath.fileSystemRepresentation,&destination,SQLITE_OPEN_READWRITE,NULL)==SQLITE_OK;
    if(ok) {
        // source holds BEGIN IMMEDIATE, so writers cannot change the committed
        // snapshot read by this second connection while the backup is made.
        (void)source;
        sqlite3_backup *backup=sqlite3_backup_init(destination,"main",read,"main");
        ok=backup!=NULL;
        if(backup) {
            CFAbsoluteTime end=CFAbsoluteTimeGetCurrent()+8;
            int status;
            do {
                status=sqlite3_backup_step(backup,128);
                if(status==SQLITE_BUSY || status==SQLITE_LOCKED) sqlite3_sleep(20);
            } while((status==SQLITE_OK || status==SQLITE_BUSY || status==SQLITE_LOCKED) && CFAbsoluteTimeGetCurrent()<end);
            ok=status==SQLITE_DONE;
            ok=(sqlite3_backup_finish(backup)==SQLITE_OK) && ok;
            if(ok) ok=integrity(destination);
        }
    }
    if(read) sqlite3_close(read);
    if(destination) sqlite3_close(destination);
    if(ok) {
        fd=open(backupPath.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW);
        if(fd<0) ok=NO;
        else { ok=fsync(fd)==0;close(fd); }
        if(ok) {
            int directory=open(backupPath.stringByDeletingLastPathComponent.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
            if(directory<0) ok=NO;
            else { ok=fsync(directory)==0;close(directory); }
        }
    }
    if(!ok) unlink(backupPath.fileSystemRepresentation);
    return ok;
}
NSDictionary *MKSKeychainClean(NSString *databasePath,NSString *backupDirectory) {
    @autoreleasepool {
        sqlite3 *db=NULL;
        BOOL transaction=NO,committed=NO,outcomeUnknown=NO;
        NSString *stage=@"open",*backupPath=nil;
        NSMutableDictionary *deleted=[NSMutableDictionary new];
        struct stat st;
        if(lstat(databasePath.fileSystemRepresentation,&st)!=0 || !S_ISREG(st.st_mode))
            return @{@"ok":@NO,@"committed":@NO,@"stage":@"database_missing",@"error":@"database_missing",
                @"retryable":@NO,@"outcomeUnknown":@NO,@"backupCreated":@NO,@"backupFormatVersion":@1};
        if(sqlite3_open_v2(databasePath.fileSystemRepresentation,&db,SQLITE_OPEN_READWRITE|SQLITE_OPEN_FULLMUTEX,NULL)!=SQLITE_OK) {
            if(db) sqlite3_close(db);
            return @{@"ok":@NO,@"committed":@NO,@"stage":stage,@"error":@"database_open_failed",
                @"retryable":@NO,@"outcomeUnknown":@NO,@"backupCreated":@NO,@"backupFormatVersion":@1};
        }
        sqlite3_busy_timeout(db,1500);
        CFAbsoluteTime end=CFAbsoluteTimeGetCurrent()+20;
        sqlite3_progress_handler(db,1000,deadline,&end);
        do {
            stage=@"schema";
            const char *tables[]={"genp","cert","keys","inet"};
            const char *counts[]={"SELECT count(*) FROM genp WHERE agrp <> 'apple'",
                "SELECT count(*) FROM cert WHERE agrp <> 'lockdown-identities'",
                "SELECT count(*) FROM keys WHERE agrp <> 'lockdown-identities'","SELECT count(*) FROM inet"};
            const char *deletes[]={"DELETE FROM genp WHERE agrp <> 'apple'",
                "DELETE FROM cert WHERE agrp <> 'lockdown-identities'",
                "DELETE FROM keys WHERE agrp <> 'lockdown-identities'","DELETE FROM inet"};
            BOOL schemaOK=YES;sqlite3_int64 value=0;
            for(int i=0;i<4;i++) if(!scalar(db,counts[i],&value)) schemaOK=NO;
            if(!schemaOK || !integrity(db)) break;
            stage=@"lock";
            if(!execSQL(db,"BEGIN IMMEDIATE")) break;
            transaction=YES;
            stage=@"backup";
            NSError *error=nil;
            if(![NSFileManager.defaultManager createDirectoryAtPath:backupDirectory withIntermediateDirectories:YES
                attributes:@{NSFilePosixPermissions:@0700} error:&error]) break;
            if(lstat(backupDirectory.fileSystemRepresentation,&st)!=0 || !S_ISDIR(st.st_mode) ||
                st.st_uid!=geteuid() || (st.st_mode&0077)) break;
            backupPath=[backupDirectory stringByAppendingPathComponent:
                [[NSUUID UUID].UUIDString stringByAppendingString:@".sqlite"]];
            if(!saveBackup(db,databasePath,backupPath)) { backupPath=nil;break; }
            stage=@"delete";
            BOOL deletionOK=YES;
            for(int i=0;i<4;i++) {
                sqlite3_int64 before=0,after=0;
                if(!scalar(db,counts[i],&before) || !execSQL(db,deletes[i]) ||
                    !scalar(db,counts[i],&after) || after!=0) { deletionOK=NO;break; }
                deleted[@(tables[i])]=@(before);
            }
            if(!deletionOK) break;
            sqlite3_int64 sequences=0;
            if(!scalar(db,"SELECT count(*) FROM sqlite_master WHERE type='table' AND name='sqlite_sequence'",&sequences)) break;
            if(sequences && !execSQL(db,"DELETE FROM sqlite_sequence")) break;
            stage=@"verify";
            if(!integrity(db)) break;
            stage=@"commit";
            if(!execSQL(db,"COMMIT")) { outcomeUnknown=YES;break; }
            transaction=NO;committed=YES;stage=@"complete";
        } while(0);
        int code=committed?SQLITE_OK:sqlite3_extended_errcode(db);
        if(transaction) {
            sqlite3_progress_handler(db,0,NULL,NULL);
            if(!sqlite3_get_autocommit(db) && !execSQL(db,"ROLLBACK")) outcomeUnknown=YES;
        }
        int checkpoint=committed?sqlite3_wal_checkpoint_v2(db,NULL,SQLITE_CHECKPOINT_PASSIVE,NULL,NULL):SQLITE_OK;
        sqlite3_close(db);
        NSMutableDictionary *result=[@{@"ok":@(committed),@"committed":@(committed),@"stage":stage,
            @"sqliteCode":@(code),@"deleted":committed?deleted:@{},@"checkpointCode":@(checkpoint),
            @"backupCreated":@(backupPath!=nil),@"backupFormatVersion":@1,
            @"retryable":@(!outcomeUnknown && [stage isEqual:@"lock"]),@"outcomeUnknown":@(outcomeUnknown)} mutableCopy];
        if(!committed) {
            NSDictionary *errors=@{@"schema":@"database_schema_unsupported",@"lock":@"resource_busy",
                @"backup":@"backup_failed",@"delete":@"cleanup_failed",@"verify":@"cleanup_verify_failed"};
            result[@"error"]=outcomeUnknown?@"cleanup_outcome_unknown":(errors[stage] ?: @"cleanup_failed");
        }
        if(backupPath) {
            result[@"backup"]=backupPath;
            result[@"backupId"]=[backupPath.lastPathComponent stringByDeletingPathExtension];
        }
        return result;
    }
}
