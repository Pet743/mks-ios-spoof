#import "../daemon/MKSHTTPServer.h"
#include <unistd.h>
#import "../daemon/MKSOperations.h"
#import "../common/MKSKeychainIPC.h"
int MKSRespring(void) {
    const char *path=getenv("MKS_TEST_RESPRING");
    FILE *f=fopen(path,"a");if(!f) return -1;fputs("respring\n",f);fclose(f);
    return getenv("MKS_TEST_RESPRING_FAIL")?-1:0;
}
int main(int argc,char **argv) {
    @autoreleasepool {
        extern void MKSCleanerStartServer(void);
        if(argc==2 && !strcmp(argv[1],"--local-server")) {
            MKSCleanerStartServer();for(;;) pause();
        }
        if(argc==2 && !strcmp(argv[1],"--local-status")) {
            NSDictionary *status=MKSRequestLocalStatus();
            NSData *data=[NSJSONSerialization dataWithJSONObject:status options:0 error:NULL];
            fwrite(data.bytes,1,data.length,stdout);puts("");return [status[@"ok"] boolValue]?0:1;
        }
        if(argc==4 && !strcmp(argv[1],"--local-bind")) {
            id previous=!strcmp(argv[3],"null")?NSNull.null:@(argv[3]);
            NSDictionary *result=MKSRequestDeviceBinding(@(argv[2]),previous);
            NSData *data=[NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
            fwrite(data.bytes,1,data.length,stdout);puts("");return [result[@"ok"] boolValue]?0:1;
        }
        if(argc==3 && !strcmp(argv[1],"--set-device-id")) return MKSHTTPConfigureDeviceID(argv[2]);
        if(argc==3 && !strcmp(argv[1],"--bind")) {
            NSData *request=[@(argv[2]) dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *body=MKSLocalSetupRequest(request);
            NSDictionary *result=body?MKSConfigureDeviceID(body[@"deviceId"],body[@"expectedDeviceId"]):@{@"ok":@NO,@"error":@"invalid_request"};
            NSData *data=[NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
            fwrite(data.bytes,1,data.length,stdout);puts("");return [result[@"ok"] boolValue]?0:1;
        }
        if(argc!=3) return 2;
        return MKSHTTPListen(@(argv[1]),@(argv[2]),0,YES)<0?1:0;
    }
}
