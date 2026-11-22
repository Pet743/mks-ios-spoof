// Typed, immutable profile snapshots shared by every MKS read path.
#import "../common/MKSProfile.h"
#include "../common/MKSBranch.h"
#include "../common/MKSPaths.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <pthread.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include <mach-o/dyld.h>
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif

typedef uint32_t io_registry_entry_t;
typedef uint32_t IOOptionBits;
static __thread unsigned int readingProfile;
static MKSProfileStore *store;
static NSDictionary *currentProfile(void) {
    if (readingProfile) return nil;
    readingProfile++;
    @try { return [store snapshot]; }
    @finally { readingProfile--; }
}
// Despite its Get name, the native MGGetStringAnswer forwards an owned result
// from the internal Copy implementation. JetEngine consumes that reference.
// Give every caller its own +1 so releasing it cannot invalidate profile values.
static CFStringRef (*orig_MGGetStringAnswer)(CFStringRef);
static CFStringRef my_MGGetStringAnswer(CFStringRef key) {
    @autoreleasepool {
        id value=key?MKSMGValue(currentProfile(),(__bridge NSString *)key):nil;
        if ([value isKindOfClass:NSString.class]) return (CFStringRef)CFBridgingRetain(value);
        return orig_MGGetStringAnswer?orig_MGGetStringAnswer(key):NULL;
    }
}
static CFTypeRef (*orig_MGCopyAnswer)(CFStringRef);
static CFTypeRef (*orig_MGCopyAnswerInternal)(CFStringRef,uint32_t *);
static CFTypeRef patchBlob(NSDictionary *profile,CFTypeRef original) {
    if(!original || CFGetTypeID(original)!=CFDictionaryGetTypeID() || ![profile[@"enabled"] boolValue]) return original;
    NSDictionary *keys=@{@"InternationalMobileEquipmentIdentity":@"InternationalMobileEquipmentIdentity",
        @"MobileEquipmentIdentifier":@"MobileEquipmentIdentifier",@"kCTPostponementInfoUniqueID":@"MobileEquipmentIdentifier"};
    NSMutableDictionary *result=[(__bridge NSDictionary *)original mutableCopy];
    for(NSString *key in keys) {
        id value=MKSMGValue(profile,keys[key]);
        if(result[key] && value) result[key]=value;
    }
    CFRelease(original);
    return CFBridgingRetain(result);
}
static CFTypeRef my_MGCopyAnswer(CFStringRef key) {
    @autoreleasepool {
        NSDictionary *p=currentProfile();
        id value=key?MKSMGValue(p,(__bridge NSString *)key):nil;
        if(value) return CFBridgingRetain(value);
        CFTypeRef original=orig_MGCopyAnswer?orig_MGCopyAnswer(key):NULL;
        return key && CFEqual(key,CFSTR("BasebandPostponementStatusBlob"))?patchBlob(p,original):original;
    }
}
static CFTypeRef my_MGCopyAnswerInternal(CFStringRef key,uint32_t *answerType) {
    @autoreleasepool {
        // This is a 32-bit MobileGestalt type output, not opaque context or
        // CFTypeID. Typed getters assert on it. Let the original populate it,
        // retaining its exact enum and unknown-key behavior on each OS build.
        CFTypeRef original=orig_MGCopyAnswerInternal?orig_MGCopyAnswerInternal(key,answerType):NULL;
        NSDictionary *p=currentProfile();
        id value=key?MKSMGValue(p,(__bridge NSString *)key):nil;
#if defined(MKS_ROOTHIDE)
        // RootHide can withhold native identity answers from a sandboxed
        // caller. Keep Copy and String getters consistent for configured
        // fields, including the internal getter's 32-bit type output.
        if(value && !original) {
            CFTypeID type=CFGetTypeID((__bridge CFTypeRef)value);
            uint32_t mgType=type==CFStringGetTypeID()?9:
                type==CFNumberGetTypeID()?6:type==CFDataGetTypeID()?10:0;
            if(mgType) {
                if(answerType) *answerType=mgType;
                return CFBridgingRetain(value);
            }
        }
#endif
        if(value && original && CFGetTypeID(original)==CFGetTypeID((__bridge CFTypeRef)value)) {
            CFRelease(original);
            return CFBridgingRetain(value);
        }
        return key && CFEqual(key,CFSTR("BasebandPostponementStatusBlob"))?patchBlob(p,original):original;
    }
}
static CFTypeRef (*orig_IORegistryEntryCreateCFProperty)(io_registry_entry_t,CFStringRef,CFAllocatorRef,IOOptionBits);
static CFTypeRef my_IORegistryEntryCreateCFProperty(io_registry_entry_t entry,CFStringRef key,CFAllocatorRef alloc,IOOptionBits options) {
    CFTypeRef original=orig_IORegistryEntryCreateCFProperty?orig_IORegistryEntryCreateCFProperty(entry,key,alloc,options):NULL;
    @autoreleasepool {
        id value=key?MKSRegistryValue(currentProfile(),(__bridge NSString *)key,(__bridge id)original):nil;
        if (!value) return original;
        CFTypeRef result=CFBridgingRetain(value);
        if(original) CFRelease(original);
        return result;
    }
}
static CFTypeRef (*orig_IORegistryEntrySearchCFProperty)(io_registry_entry_t,const char *,CFStringRef,CFAllocatorRef,IOOptionBits);
static CFTypeRef my_IORegistryEntrySearchCFProperty(io_registry_entry_t entry,const char *plane,CFStringRef key,CFAllocatorRef alloc,IOOptionBits options) {
    CFTypeRef original=orig_IORegistryEntrySearchCFProperty?orig_IORegistryEntrySearchCFProperty(entry,plane,key,alloc,options):NULL;
    @autoreleasepool {
        id value=key?MKSRegistryValue(currentProfile(),(__bridge NSString *)key,(__bridge id)original):nil;
        if (!value) return original;
        CFTypeRef result=CFBridgingRetain(value);
        if(original) CFRelease(original);
        return result;
    }
}
static CFDictionaryRef (*orig_CFCopySystemVersionDictionary)(void);
static CFDictionaryRef my_CFCopySystemVersionDictionary(void) {
    CFDictionaryRef original=orig_CFCopySystemVersionDictionary?orig_CFCopySystemVersionDictionary():NULL;
    if(!original) return NULL;
    @autoreleasepool {
        NSDictionary *p=currentProfile();
        NSString *version=MKSMGValue(p,@"ProductVersion"), *build=MKSMGValue(p,@"BuildVersion");
        if (!version && !build) return original;
        NSMutableDictionary *result=[(__bridge NSDictionary *)original mutableCopy];
        if(version) { result[@"ProductVersion"]=version; result[@"ShortVersionString"]=version; }
        if(build) result[@"ProductBuildVersion"]=build;
        if(version && build) result[@"FullVersionString"]=[NSString stringWithFormat:@"Version %@ (Build %@)",version,build];
        CFRelease(original);
        return CFBridgingRetain(result);
    }
}
static id (*orig_idfv)(id,SEL);
static id my_idfv(id self,SEL cmd) {
    NSString *uuid=MKSProfileUUID(currentProfile());
    return uuid?[[NSUUID alloc] initWithUUIDString:uuid]:(orig_idfv?orig_idfv(self,cmd):nil);
}
static id (*orig_idfa)(id,SEL);
static id my_idfa(id self,SEL cmd) {
    id original=orig_idfa?orig_idfa(self,cmd):nil;
    // Keep the all-zero identifier returned when advertising tracking is denied.
    if ([original isKindOfClass:NSUUID.class] && [[original UUIDString] isEqual:@"00000000-0000-0000-0000-000000000000"]) return original;
    NSString *uuid=MKSProfileUUID(currentProfile());
    return uuid?[[NSUUID alloc] initWithUUIDString:uuid]:original;
}
static BOOL objectSetter(id obj,SEL selector,NSString *value) {
    Method method=class_getInstanceMethod(object_getClass(obj),selector);
    char result[8]={0},argument[8]={0};
    if(!method || method_getNumberOfArguments(method)!=3) return NO;
    method_getReturnType(method,result,sizeof(result));method_getArgumentType(method,2,argument,sizeof(argument));
    if(result[0]!='v' || argument[0]!='@') return NO;
    ((void (*)(id,SEL,id))objc_msgSend)(obj,selector,value);
    return YES;
}
static id (*orig_equipment)(id,SEL);
static id my_equipment(id self,SEL cmd) {
    id original=orig_equipment?orig_equipment(self,cmd):nil;
    NSDictionary *p=currentProfile();
    if(![original isKindOfClass:NSDictionary.class] || ![p[@"enabled"] boolValue]) return original;
    NSString *imei=MKSMGValue(p,@"InternationalMobileEquipmentIdentity"),*meid=MKSMGValue(p,@"MobileEquipmentIdentifier");
    if(!imei && !meid) return original;
    for(id key in original) {
        id item=original[key];
        if(![item conformsToProtocol:@protocol(NSCopying)]) continue;
        id copy=[item copy];
        if(copy==item) continue; // A cached original must remain unchanged for disable/restore.
        BOOL changed=NO;
        if(imei) changed|=objectSetter(copy,sel_registerName("setIMEI:"),imei);
        if(meid) changed|=objectSetter(copy,sel_registerName("setMEID:"),meid);
        if(changed) { NSMutableDictionary *result=[original mutableCopy];result[key]=copy;return result; }
    }
    return original;
}
static id (*orig_deviceBuild)(id,SEL);
static id my_deviceBuild(id self,SEL cmd) {
    return MKSMGValue(currentProfile(),@"BuildVersion") ?: (orig_deviceBuild?orig_deviceBuild(self,cmd):nil);
}
static NSString *sysctlValue(NSDictionary *profile,const char *name) {
    if(!name) return nil;
    if(!strcmp(name,"hw.machine")) return MKSMGValue(profile,@"ProductType");
    if(!strcmp(name,"hw.model")) return MKSMGValue(profile,@"HWModelStr");
    if(!strcmp(name,"kern.osproductversion")) return MKSMGValue(profile,@"ProductVersion");
    if(!strcmp(name,"kern.osversion")) return MKSMGValue(profile,@"BuildVersion");
    return nil;
}
static int (*orig_sysctlbyname)(const char *,void *,size_t *,void *,size_t);
static int __attribute__((unused)) my_sysctlbyname(const char *name,void *out,size_t *len,void *newp,size_t newlen) {
    if(!newp && !newlen) {
        NSString *value=sysctlValue(currentProfile(),name);
        if(value) return MKSStringSysctl(value,out,len);
    }
    return orig_sysctlbyname?orig_sysctlbyname(name,out,len,newp,newlen):-1;
}
static int (*orig_sysctl)(int *,u_int,void *,size_t *,void *,size_t);
static int __attribute__((unused)) my_sysctl(int *name,u_int count,void *out,size_t *len,void *newp,size_t newlen) {
    if(name && count==2 && !newp && !newlen) {
        const char *key=NULL;
        if(name[0]==CTL_HW && name[1]==HW_MACHINE) key="hw.machine";
        if(name[0]==CTL_HW && name[1]==HW_MODEL) key="hw.model";
        if(name[0]==CTL_KERN && name[1]==KERN_OSVERSION) key="kern.osversion";
        NSString *value=sysctlValue(currentProfile(),key);
        if(value) return MKSStringSysctl(value,out,len);
    }
    return orig_sysctl?orig_sysctl(name,count,out,len,newp,newlen):-1;
}

#ifndef MKS_UNIT_TEST
typedef void (*HookFunction)(void *,void *,void **);
typedef void (*HookMessage)(Class,SEL,IMP,IMP *);
static void hook(HookFunction install,const char *name,void *replacement,void **original) {
    void *target=dlsym(RTLD_DEFAULT,name);
    if(target && install) install(target,replacement,original);
}
static void hookMG(HookFunction install) {
    void *symbol=dlsym(RTLD_DEFAULT,"MGCopyAnswer");
    if(!symbol) return;
    void *code=symbol;
#if __has_feature(ptrauth_calls)
    code=ptrauth_strip(code,ptrauth_key_function_pointer);
#endif
    uintptr_t target=MKSBranchTarget(code,8,(uintptr_t)code);
    Dl_info from={0},to={0};
    if(target && !(target&3) && dladdr(code,&from) && dladdr((void *)target,&to) && from.dli_fbase==to.dli_fbase) {
        install((void *)target,(void *)my_MGCopyAnswerInternal,(void **)&orig_MGCopyAnswerInternal);
    } else {
        install(symbol,(void *)my_MGCopyAnswer,(void **)&orig_MGCopyAnswer);
    }
}
static BOOL hookObjectGetter(HookMessage install,const char *className,const char *selectorName,IMP replacement,IMP *original) {
    Class cls=objc_getClass(className);SEL selector=sel_registerName(selectorName);
    Method method=class_getInstanceMethod(cls,selector);char type[8]={0};
    if(!install || !method || method_getNumberOfArguments(method)!=2) return NO;
    method_getReturnType(method,type,sizeof(type));
    if(type[0]!='@') return NO;
    install(cls,selector,replacement,original);return YES;
}
static void installPrivateGetters(HookMessage message) {
    // Private frameworks can arrive after the injection constructor.
    static BOOL equipmentInstalled,buildInstalled;
    if(!equipmentInstalled) equipmentInstalled=hookObjectGetter(message,"PSUICoreTelephonySubscriberCache","mobileEquipmentInfoDict",(IMP)my_equipment,(IMP *)&orig_equipment);
    if(!buildInstalled) buildInstalled=hookObjectGetter(message,"AADeviceInfo","buildVersion",(IMP)my_deviceBuild,(IMP *)&orig_deviceBuild);
}
static HookMessage privateMessageInstaller;
static volatile int getterInstallPending;
static void onImageLoaded(const struct mach_header *header,intptr_t slide) {
    (void)header;(void)slide;
    if(!__sync_bool_compare_and_swap(&getterInstallPending,0,1)) return;
    dispatch_async(dispatch_get_main_queue(),^{
        __sync_lock_release(&getterInstallPending);
        installPrivateGetters(privateMessageInstaller);
    });
}
__attribute__((constructor)) static void mks_init(void) {
    @autoreleasepool {
        store=[[MKSProfileStore alloc] initWithPaths:MKSConfigPaths()];
        void *framework=dlopen(MKS_JB_PATH("/usr/lib/libellekit.dylib"),RTLD_NOW|RTLD_GLOBAL);
        if(!framework) framework=dlopen(MKS_JB_PATH("/usr/lib/libsubstrate.dylib"),RTLD_NOW|RTLD_GLOBAL);
        HookFunction install=(HookFunction)dlsym(RTLD_DEFAULT,"MSHookFunction");
        HookMessage message=(HookMessage)dlsym(RTLD_DEFAULT,"MSHookMessageEx");
        if(!install) { NSLog(@"MKS: hook framework unavailable; no hooks installed"); return; }
        dlopen("/usr/lib/libMobileGestalt.dylib",RTLD_LAZY|RTLD_GLOBAL);
        dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",RTLD_LAZY|RTLD_GLOBAL);
        hook(install,"MGGetStringAnswer",(void *)my_MGGetStringAnswer,(void **)&orig_MGGetStringAnswer);
        hookMG(install);
        hook(install,"IORegistryEntryCreateCFProperty",(void *)my_IORegistryEntryCreateCFProperty,(void **)&orig_IORegistryEntryCreateCFProperty);
        hook(install,"IORegistryEntrySearchCFProperty",(void *)my_IORegistryEntrySearchCFProperty,(void **)&orig_IORegistryEntrySearchCFProperty);
#if defined(MKS_ROOTHIDE)
        if([NSProcessInfo.processInfo.processName isEqual:@"Preferences"])
            hook(install,"_CFCopySystemVersionDictionary",(void *)my_CFCopySystemVersionDictionary,(void **)&orig_CFCopySystemVersionDictionary);
#else
        hook(install,"_CFCopySystemVersionDictionary",(void *)my_CFCopySystemVersionDictionary,(void **)&orig_CFCopySystemVersionDictionary);
        hook(install,"sysctlbyname",(void *)my_sysctlbyname,(void **)&orig_sysctlbyname);
        hook(install,"sysctl",(void *)my_sysctl,(void **)&orig_sysctl);
#endif
        Class device=objc_getClass("UIDevice");
        SEL idfv=sel_registerName("identifierForVendor");
        if(message && class_getInstanceMethod(device,idfv)) message(device,idfv,(IMP)my_idfv,(IMP *)&orig_idfv);
        dlopen("/System/Library/Frameworks/AdSupport.framework/AdSupport",RTLD_LAZY|RTLD_GLOBAL);
        Class ads=objc_getClass("ASIdentifierManager");
        SEL advertising=sel_registerName("advertisingIdentifier");
        if(message && class_getInstanceMethod(ads,advertising)) message(ads,advertising,(IMP)my_idfa,(IMP *)&orig_idfa);
        installPrivateGetters(message);
        privateMessageInstaller=message;
        _dyld_register_func_for_add_image(onImageLoaded);
        NSLog(@"MKS 1.15.3: MG=%d/%d IO=%d/%d sysctl=%d/%d",orig_MGCopyAnswer!=NULL || orig_MGCopyAnswerInternal!=NULL,orig_MGGetStringAnswer!=NULL,
            orig_IORegistryEntryCreateCFProperty!=NULL,orig_IORegistryEntrySearchCFProperty!=NULL,orig_sysctl!=NULL,orig_sysctlbyname!=NULL);
    }
}
#endif
