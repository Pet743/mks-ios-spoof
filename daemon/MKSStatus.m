#import "../common/MKSProfile.h"

const char *MKSStatus(void) {
    @autoreleasepool {
        static MKSProfileStore *store;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ store=[[MKSProfileStore alloc] initWithPaths:MKSConfigPaths()]; });
        NSDictionary *p=[store snapshot];
        if(!p) return "MISSING_OR_INVALID";
        return [p[@"enabled"] boolValue]?"ENABLED":"DISABLED";
    }
}
