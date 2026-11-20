#import "../common/MKSKeychain.h"
#import "../common/MKSKeychainIPC.h"

int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc==3) {
            NSDictionary *result=MKSKeychainClean(@(argv[1]),@(argv[2]));
            NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:NULL];
            fwrite(json.bytes,1,json.length,stdout);fputc('\n',stdout);
            return [result[@"ok"] boolValue]?0:1;
        }
        if(argc==4 && !strcmp(argv[1],"--ipc")) {
            NSString *expected=@(argv[2]),*other=@(argv[3]);
            if(!MKSKeychainRequestValid([@(MKS_KEYCHAIN_COMMAND) dataUsingEncoding:NSUTF8StringEncoding])) return 1;
            for(NSString *bad in @[@"",@"CLEAN_KEYCHAIN",@"CLEAN_KEYCHAIN_V1",@"CLEAN_KEYCHAIN_V1\nextra",@"PING",@"RESPRING"])
                if(MKSKeychainRequestValid([bad dataUsingEncoding:NSUTF8StringEncoding])) return 2;
            if(!MKSKeychainPeerAllowed(501,expected,expected) || !MKSKeychainPeerAllowed(0,expected,expected)) return 3;
            if(MKSKeychainPeerAllowed(502,expected,expected) || MKSKeychainPeerAllowed(501,other,expected)) return 4;
            if(MKSKeychainPeerAllowed(501,[expected stringByAppendingString:@"extra"],expected)) return 5;
            puts("IPC exact_request=PASS; peer_uid_and_executable=PASS");
            return 0;
        }
        return 2;
    }
}
