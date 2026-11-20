#import "MKSKeychainIPC.h"
#include <TargetConditionals.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <errno.h>

BOOL MKSKeychainRequestValid(NSData *request) {
    const char command[]=MKS_KEYCHAIN_COMMAND;
    return request.length==sizeof(command)-1 && !memcmp(request.bytes,command,sizeof(command)-1);
}
BOOL MKSKeychainPeerAllowed(uid_t uid,NSString *processPath,NSString *appPath) {
    if(uid!=0 && uid!=501) return NO;
    if(!processPath.length || !appPath.length) return NO;
    char peer[PATH_MAX],expected[PATH_MAX];
    if(!realpath(processPath.fileSystemRepresentation,peer) || !realpath(appPath.fileSystemRepresentation,expected)) return NO;
    return !strcmp(peer,expected);
}
NSDictionary *MKSRequestKeychainClean(void) {
#if TARGET_OS_SIMULATOR
    return @{@"ok":@NO,@"committed":@NO,@"stage":@"simulator"};
#else
    int fd=socket(AF_UNIX,SOCK_STREAM,0);
    if(fd<0) return @{@"ok":@NO,@"committed":@NO,@"stage":@"connection"};
    int yes=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    struct timeval timeout={30,0};
    setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
    struct sockaddr_un address={0};address.sun_family=AF_UNIX;
    strlcpy(address.sun_path,MKS_KEYCHAIN_SOCKET,sizeof(address.sun_path));
    NSDictionary *result=nil;BOOL requested=NO;
    if(connect(fd,(struct sockaddr *)&address,sizeof(address))==0) {
        const char command[]=MKS_KEYCHAIN_COMMAND;
        size_t sent=0;
        while(sent<sizeof(command)-1) {
            ssize_t n=write(fd,command+sent,sizeof(command)-1-sent);
            if(n<0 && errno==EINTR) continue;
            if(n<=0) break;
            sent+=(size_t)n;
        }
        requested=sent==sizeof(command)-1;
        shutdown(fd,SHUT_WR);
        NSMutableData *response=[NSMutableData new];
        char buffer[1024];ssize_t n;
        BOOL complete=NO;
        while(response.length<=16384) {
            n=read(fd,buffer,sizeof(buffer));
            if(n<0 && errno==EINTR) continue;
            if(n==0) { complete=YES;break; }
            if(n<0) break;
            [response appendBytes:buffer length:(NSUInteger)n];
        }
        if(complete && response.length<=16384) {
            id value=[NSJSONSerialization JSONObjectWithData:response options:0 error:NULL];
            if([value isKindOfClass:NSDictionary.class]) result=value;
        }
    }
    close(fd);
    // Do not retry automatically: a lost response may follow a committed delete.
    return result ?: @{@"ok":@NO,@"committed":@NO,@"outcomeUnknown":@(requested),@"stage":@"connection"};
#endif
}
