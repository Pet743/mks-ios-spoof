#import "MKSHTTPServer.h"
#import "../common/MKSHTTP.h"
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>

static NSDictionary *setupError(NSString *error,BOOL retryable,BOOL unknown) {
    return @{@"ok":@NO,@"error":error,@"stage":@"device_setup",@"retryable":@(retryable),
        @"requiresLocalSetup":@YES,@"outcomeUnknown":@(unknown)};
}
static BOOL syncDirectory(NSString *directory) {
    int fd=open(directory.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    if(fd<0) return NO;
    BOOL ok=fsync(fd)==0;close(fd);return ok;
}
// Final file names are fixed by the daemon. Stage data and permissions before publication.
static BOOL writeState(NSString *value,NSString *path,BOOL exclusive,BOOL *published) {
    *published=NO;
    NSString *temporary=[path stringByAppendingFormat:@".%@.tmp",NSUUID.UUID.UUIDString];
    NSData *data=[value dataUsingEncoding:NSUTF8StringEncoding];
    int fd=open(temporary.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if(fd<0) return NO;
    BOOL ok=YES;size_t offset=0;
    while(offset<data.length) {
        ssize_t written=write(fd,(const char *)data.bytes+offset,data.length-offset);
        if(written<0 && errno==EINTR) continue;
        if(written<=0) { ok=NO;break; }
        offset+=(size_t)written;
    }
#ifndef MKS_HTTP_TEST
    if(fchown(fd,0,501)!=0) ok=NO;
#endif
    if(fchmod(fd,0640)!=0 || fsync(fd)!=0) ok=NO;
    if(close(fd)!=0) ok=NO;
    NSString *readback=[NSString stringWithContentsOfFile:temporary encoding:NSUTF8StringEncoding error:NULL];
    if(![readback isEqual:value]) ok=NO;
    if(ok) {
        int result=exclusive?link(temporary.fileSystemRepresentation,path.fileSystemRepresentation):
            rename(temporary.fileSystemRepresentation,path.fileSystemRepresentation);
        ok=result==0;*published=ok;
    }
    unlink(temporary.fileSystemRepresentation);
    if(*published && !syncDirectory(path.stringByDeletingLastPathComponent)) ok=NO;
    return ok;
}
BOOL MKSPrepareInstallation(NSString *directory) {
    NSString *path=[directory stringByAppendingPathComponent:@"installation-id"];
    struct stat st;
    if(lstat(path.fileSystemRepresentation,&st)==0)
        return S_ISREG(st.st_mode) && MKSHTTPInstallationID()!=nil;
    if(errno!=ENOENT) return NO;
    BOOL published=NO;
    if(writeState(NSUUID.UUID.UUIDString,path,YES,&published)) return YES;
    // Another initializer may have published the same installation's identity.
    return !published && MKSHTTPInstallationID()!=nil;
}
NSDictionary *MKSConfigureDeviceID(NSString *deviceID,id expectedDeviceID) {
    @synchronized(NSProcessInfo.processInfo) {
        uid_t uid=geteuid();
#ifdef MKS_HTTP_TEST
        uid=(uid_t)strtoul(getenv("MKS_TEST_SETUP_UID") ?: "501",NULL,10);
#endif
        if(uid!=0) return setupError(@"permission_denied",NO,NO);
        NSString *normalized=MKSNormalizeDeviceID(deviceID);
        if(!normalized) return setupError(@"invalid_device_id",NO,NO);
        NSString *directory=MKSHTTPStateDirectory();
        struct stat st;
        if(lstat(directory.fileSystemRepresentation,&st)!=0 || !S_ISDIR(st.st_mode) || (st.st_mode&0027))
            return setupError(@"state_directory_unavailable",NO,NO);
#ifndef MKS_HTTP_TEST
        if(st.st_uid!=0) return setupError(@"state_directory_unavailable",NO,NO);
#endif
        NSString *lockPath=[directory stringByAppendingPathComponent:@"setup.lock"];
        int lock=open(lockPath.fileSystemRepresentation,O_WRONLY|O_CREAT|O_NOFOLLOW,0600);
        if(lock<0) return setupError(@"persistence_failed",NO,NO);
        if(flock(lock,LOCK_EX|LOCK_NB)!=0) { close(lock);return setupError(@"resource_busy",YES,NO); }
        @try {
            NSString *path=[directory stringByAppendingPathComponent:@"device-id"];
            BOOL exists=lstat(path.fileSystemRepresentation,&st)==0;
            if(!exists && errno!=ENOENT) return setupError(@"persistence_failed",NO,NO);
            NSString *previous=MKSHTTPDeviceID();
            if(exists && (!S_ISREG(st.st_mode) || !previous)) return setupError(@"device_id_state_invalid",NO,NO);
            if(expectedDeviceID && ![(previous ?: NSNull.null) isEqual:expectedDeviceID])
                return setupError(@"device_id_changed",NO,NO);
            BOOL published=NO;
            if(!writeState(normalized,path,NO,&published)) return setupError(@"persistence_failed",NO,published);
            NSString *effective=MKSHTTPDeviceID();
            if(![effective isEqual:normalized]) return setupError(@"device_id_readback_failed",NO,YES);
            return @{@"ok":@YES,@"configured":@YES,@"deviceId":effective,@"outcomeUnknown":@NO};
        } @finally { flock(lock,LOCK_UN);close(lock); }
    }
}
int MKSHTTPConfigureDeviceID(const char *deviceID) {
    @autoreleasepool {
        NSDictionary *result=MKSConfigureDeviceID(deviceID?@(deviceID):nil,nil);
        NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:NULL];
        fwrite(data.bytes,1,data.length,stdout);fputc('\n',stdout);fflush(stdout);
        if([result[@"ok"] boolValue]) return 0;
        NSDictionary *codes=@{@"permission_denied":@1,@"invalid_device_id":@2,@"resource_busy":@5};
        return codes[result[@"error"]]?[codes[result[@"error"]] intValue]:3;
    }
}
