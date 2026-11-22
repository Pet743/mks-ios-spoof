#import "MKSOperations.h"
#include "../common/MKSPaths.h"
#import "../common/MKSProfile.h"
#import "../common/MKSKeychain.h"
#import "../common/MKSHTTP.h"
#include <unistd.h>

static NSLock *operationLock(void) {
    static NSLock *lock;static dispatch_once_t once;
    dispatch_once(&once,^{lock=[NSLock new];});return lock;
}
static NSString *profilePath(void) {
#ifdef MKS_HTTP_TEST
    return @(getenv("MKS_TEST_CONFIG"));
#else
    return MKSConfigPath();
#endif
}
NSDictionary *MKSOperationStatus(void) {
    MKSProfileStore *store=[[MKSProfileStore alloc] initWithPaths:@[profilePath()]];
    NSDictionary *profile=[store snapshot];
    NSString *device=MKSHTTPDeviceID();
#if defined(MKS_ROOTHIDE)
    NSString *environment=@"roothide";
#else
    NSString *environment=@"rootless";
#endif
    return @{@"ok":@YES,@"apiVersion":@1,@"deviceConfigured":@((BOOL)(device!=nil)),
        @"environment":@{@"jailbreak":environment,@"layoutVersion":@1},
        @"capabilities":@{@"spoof":@YES,@"restore":@YES,@"keychainClean":@YES},
        @"installationId":MKSHTTPInstallationID() ?: NSNull.null,@"version":@"1.14.1",@"enabled":@([profile[@"enabled"] boolValue]),
        @"profileValid":@((BOOL)(profile!=nil)),@"deviceId":device ?: NSNull.null};
}
NSDictionary *MKSPerformOperation(NSString *action) {
    [operationLock() lock];
    @try {
        if([action isEqual:@"keychain/clean"]) {
#ifdef MKS_HTTP_TEST
            return MKSKeychainClean(@(getenv("MKS_TEST_KEYCHAIN")),@(getenv("MKS_TEST_BACKUPS")));
#else
            return MKSKeychainClean(@"/var/Keychains/keychain-2.db",MKS_JB_NS_PATH("/var/lib/mks-keychain-backups"));
#endif
        }
        if(![@[@"spoof",@"restore"] containsObject:action]) return @{@"ok":@NO,@"error":@"unknown_action"};
        NSDictionary *profile=[action isEqual:@"spoof"]?MKSGenerateProfile():
            @{@"schemaVersion":@2,@"enabled":@NO,@"name":@"已停用",@"values":@{}};
        NSError *error=nil;
        if(!MKSWriteProfile(profile,profilePath(),&error)) return @{@"ok":@NO,@"profileSaved":@NO,@"error":@"profile_save_failed",@"stage":@"profile_save",@"retryable":@NO,@"outcomeUnknown":@NO};
        // Atomic writes by the root daemon must remain writable by the mobile UI.
#ifndef MKS_HTTP_TEST
        if(chown(profilePath().fileSystemRepresentation,501,501)!=0) return @{@"ok":@NO,@"profileSaved":@YES,@"error":@"profile_owner_failed",@"stage":@"profile_owner",@"retryable":@NO,@"outcomeUnknown":@NO};
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR("com.mks.spoof.changed"),NULL,NULL,true);
#endif
        BOOL restarted=MKSRespring()==0;
        return @{@"ok":@(restarted),@"profileSaved":@YES,@"enabled":profile[@"enabled"],
            @"respringCommandSucceeded":@(restarted),@"error":restarted?NSNull.null:@"respring_failed",
            @"stage":restarted?@"complete":@"respring",@"retryable":@NO,@"outcomeUnknown":@NO};
    } @finally { [operationLock() unlock]; }
}
