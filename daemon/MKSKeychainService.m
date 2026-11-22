#import "../common/MKSKeychain.h"
#import "../common/MKSKeychainIPC.h"
#import "MKSOperations.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <dlfcn.h>
#include <unistd.h>
#include <errno.h>

static BOOL authorized(int fd) {
    uid_t uid;gid_t gid;pid_t pid=0;socklen_t size=sizeof(pid);
    if(getpeereid(fd,&uid,&gid)!=0 || getsockopt(fd,SOL_LOCAL,LOCAL_PEERPID,&pid,&size)!=0 || pid<=0) return NO;
    typedef int (*ProcessPath)(int,void *,uint32_t);
    ProcessPath path=(ProcessPath)dlsym(RTLD_DEFAULT,"proc_pidpath");
    char process[4096]={0};
    if(!path || path(pid,process,sizeof(process))<=0) return NO;
    return MKSKeychainPeerAllowed(uid,@(process),MKS_JB_NS_PATH("/Applications/MKS.app/MKS"));
}
static void serveClient(int fd) {
    struct timeval timeout={4,0};int yes=1;
    setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
    setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    NSDictionary *result=@{@"ok":@NO,@"committed":@NO,@"stage":@"unauthorized"};
    if(authorized(fd)) {
        NSMutableData *request=[NSMutableData new];char buffer[64];ssize_t n;BOOL complete=NO;
        while(request.length<=64) {
            n=read(fd,buffer,sizeof(buffer));
            if(n<0 && errno==EINTR) continue;
            if(n==0) { complete=YES;break; }
            if(n<0) break;
            [request appendBytes:buffer length:(NSUInteger)n];
        }
        result=@{@"ok":@NO,@"committed":@NO,@"stage":@"invalid_request"};
        if(complete && MKSKeychainRequestValid(request)) {
            result=MKSPerformOperation(@"keychain/clean");
        }
    }
    NSData *data=[NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
    size_t sent=0;
    while(sent<data.length) {
        ssize_t n=write(fd,(const uint8_t *)data.bytes+sent,data.length-sent);
        if(n<0 && errno==EINTR) continue;
        if(n<=0) break;
        sent+=(size_t)n;
    }
}
void MKSCleanerStartServer(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        @autoreleasepool {
            const char *socketPath=MKS_KEYCHAIN_SOCKET;
            struct sockaddr_un address={0};address.sun_family=AF_UNIX;
            if(strlcpy(address.sun_path,socketPath,sizeof(address.sun_path))>=sizeof(address.sun_path)) return;
            struct stat st;
            if(lstat(socketPath,&st)==0) {
                if(!S_ISSOCK(st.st_mode) || st.st_uid!=0) return;
                if(unlink(socketPath)!=0) return;
            }
            int server=socket(AF_UNIX,SOCK_STREAM,0);
            if(server<0) return;
            if(bind(server,(struct sockaddr *)&address,sizeof(address))!=0 ||
                chown(socketPath,0,501)!=0 || chmod(socketPath,0660)!=0 || listen(server,4)!=0) {
                close(server);return;
            }
            while(1) {
                int client=accept(server,NULL,NULL);
                if(client<0) { if(errno==EINTR) continue;break; }
                @autoreleasepool { serveClient(client); }
                close(client);
            }
            close(server);unlink(socketPath);
        }
    });
}
