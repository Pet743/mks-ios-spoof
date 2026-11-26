// Temporary in-process read-only diagnostics. Not included in release DEBs.
#import <Foundation/Foundation.h>
#import "../common/MKSProfile.h"
#include <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <sys/sysctl.h>
#include <sys/stat.h>
#include <unistd.h>

typedef uint32_t IOEntry;
static NSString *fingerprint(id value) {
    if (!value) return @"missing";
    NSData *bytes=[value isKindOfClass:NSData.class]?value:[[value description] dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes.bytes,(CC_LONG)bytes.length,digest);
    NSMutableString *result=[NSMutableString new];
    for (NSUInteger i=0;i<sizeof(digest);i++) [result appendFormat:@"%02x",digest[i]];
    return result;
}
static void emit(NSDictionary *payload) {
    NSMutableDictionary *result=[payload mutableCopy];
    result[@"run"]=@"roothide-1.15-20261123";
    result[@"process"]=NSProcessInfo.processInfo.processName;
    result[@"pid"]=@(getpid());
    NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:NULL];
    NSLog(@"MKSVERIFY %@",[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
}
static void answer(NSString *phase,NSString *api,NSString *key,id actual,id expected) {
    NSString *status=!expected?@"passthrough":!actual?@"missing":[actual isEqual:expected]?@"match":@"mismatch";
    emit(@{@"phase":phase,@"api":api,@"key":key,@"status":status,@"digest":fingerprint(actual)});
}
static void sample(NSDictionary *profile,NSError *readError,BOOL readable) {
    NSString *phase=[profile[@"enabled"] boolValue]?@"enabled":@"disabled";
    BOOL loaded=NO;
    for (uint32_t i=0;i<_dyld_image_count();i++) {
        const char *name=_dyld_get_image_name(i);
        if (name && [[[NSString stringWithUTF8String:name] lastPathComponent] isEqual:@"mks.dylib"]) loaded=YES;
    }
    emit(@{@"phase":phase,@"api":@"metadata",@"configReadable":@(readable),@"profileValid":@((BOOL)(profile!=nil)),
           @"readError":@(readError.code),@"mksLoaded":@(loaded)});
    if (!profile) return;
    CFTypeRef (*copy)(CFStringRef)=dlsym(RTLD_DEFAULT,"MGCopyAnswer");
    CFStringRef (*string)(CFStringRef)=dlsym(RTLD_DEFAULT,"MGGetStringAnswer");
    NSArray *keys=@[@"ProductType",@"ProductVersion",@"BuildVersion",@"HWModelStr",@"HardwarePlatform",@"SerialNumber",
        @"MLBSerialNumber",@"UniqueDeviceID",@"UniqueChipID",@"DieId",@"ChipID",@"WifiAddress",@"BluetoothAddress",
        @"ModelNumber",@"RegionInfo",@"RegionCode",@"InternationalMobileEquipmentIdentity",@"InternationalMobileEquipmentIdentity2",
        @"MobileEquipmentIdentifier",@"ProductName"];
    for (NSString *key in keys) {
        id expected=MKSMGValue(profile,key);
        if (copy) {
            CFTypeRef value=copy((__bridge CFStringRef)key);
            answer(phase,@"MGCopyAnswer",key,(__bridge id)value,expected);
            if (value) CFRelease(value);
        }
        // Only ask the typed string getter about string-valued keys.
        if (string && ![@[@"UniqueChipID",@"DieId",@"ChipID"] containsObject:key]) {
            CFStringRef value=string((__bridge CFStringRef)key);
            answer(phase,@"MGGetStringAnswer",key,(__bridge id)value,expected);
            if (value) CFRelease(value);
        }
    }
    int (*sys)(const char *,void *,size_t *,void *,size_t)=dlsym(RTLD_DEFAULT,"sysctlbyname");
    NSDictionary *syskeys=@{@"hw.machine":@"ProductType",@"hw.model":@"HWModelStr",@"kern.osproductversion":@"ProductVersion",@"kern.osversion":@"BuildVersion"};
    if (sys) for (NSString *key in syskeys) {
        char buffer[512]={0};size_t length=sizeof(buffer);
        id actual=sys(key.UTF8String,buffer,&length,NULL,0)==0?[NSString stringWithUTF8String:buffer]:nil;
        answer(phase,@"sysctlbyname",key,actual,MKSMGValue(profile,syskeys[key]));
    }
    int (*sysMIB)(int *,u_int,void *,size_t *,void *,size_t)=dlsym(RTLD_DEFAULT,"sysctl");
    if (sysMIB) {
        int mib[]={CTL_HW,HW_MACHINE};char buffer[512]={0};size_t length=sizeof(buffer);
        id actual=sysMIB(mib,2,buffer,&length,NULL,0)==0?[NSString stringWithUTF8String:buffer]:nil;
        answer(phase,@"sysctl",@"hw.machine",actual,MKSMGValue(profile,@"ProductType"));
    }
    CFDictionaryRef (*systemVersion)(void)=dlsym(RTLD_DEFAULT,"_CFCopySystemVersionDictionary");
    if (systemVersion) {
        CFDictionaryRef value=systemVersion();
        NSDictionary *version=(__bridge NSDictionary *)value;
        answer(phase,@"systemVersion",@"ProductVersion",version[@"ProductVersion"],MKSMGValue(profile,@"ProductVersion"));
        answer(phase,@"systemVersion",@"ProductBuildVersion",version[@"ProductBuildVersion"],MKSMGValue(profile,@"BuildVersion"));
        if (value) CFRelease(value);
    }
    CFMutableDictionaryRef (*matching)(const char *)=dlsym(RTLD_DEFAULT,"IOServiceMatching");
    IOEntry (*service)(uint32_t,CFDictionaryRef)=dlsym(RTLD_DEFAULT,"IOServiceGetMatchingService");
    int (*release)(IOEntry)=dlsym(RTLD_DEFAULT,"IOObjectRelease");
    CFTypeRef (*property)(IOEntry,CFStringRef,CFAllocatorRef,uint32_t)=dlsym(RTLD_DEFAULT,"IORegistryEntryCreateCFProperty");
    CFTypeRef (*search)(IOEntry,const char *,CFStringRef,CFAllocatorRef,uint32_t)=dlsym(RTLD_DEFAULT,"IORegistryEntrySearchCFProperty");
    if (matching && service && property) {
        IOEntry entry=service(0,matching("IOPlatformExpertDevice"));
        if (entry) for (NSString *key in @[@"IOPlatformSerialNumber",@"IOPlatformUUID",@"unique-chip-id",@"die-id",@"board-id",@"mac-address-wifi0",@"mac-address-bluetooth0"]) {
            CFTypeRef value=property(entry,(__bridge CFStringRef)key,NULL,0);
            answer(phase,@"IORegistryCreate",key,(__bridge id)value,MKSRegistryValue(profile,key,(__bridge id)value));
            if (value) CFRelease(value);
            if (search) {
                value=search(entry,"IOService",(__bridge CFStringRef)key,NULL,3);
                answer(phase,@"IORegistrySearch",key,(__bridge id)value,MKSRegistryValue(profile,key,(__bridge id)value));
                if (value) CFRelease(value);
            }
        }
        if (entry && release) release(entry);
    }
}
__attribute__((constructor)) static void verify_init(void) {
    dispatch_queue_t queue=dispatch_queue_create("mks.readonly.verify",DISPATCH_QUEUE_SERIAL);
    dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,queue);
    __block NSString *last=nil;__block NSUInteger count=0;
    dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),NSEC_PER_SEC,100*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer,^{ @autoreleasepool {
        NSError *error=nil;
        NSData *data=[NSData dataWithContentsOfFile:MKSConfigPath() options:0 error:&error];
        NSString *current=data?fingerprint(data):[NSString stringWithFormat:@"error:%ld",(long)error.code];
        if (![last isEqual:current]) {
            last=current;
            sample(data?MKSParseProfile(data,NULL):nil,error,data!=nil);
        }
        if (++count>=240) dispatch_source_cancel(timer);
    }});
    dispatch_resume(timer);
}
