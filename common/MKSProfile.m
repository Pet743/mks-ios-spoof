#import "MKSProfile.h"
#include <TargetConditionals.h>
#include <sys/stat.h>
#include <errno.h>
#include <string.h>

NSString *MKSConfigPath(void) {
#if TARGET_OS_SIMULATOR
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"mks.config"];
#else
    // Sandboxed App Store/AuthKit processes cannot read mobile's Media directory.
    // The jailbreak root is readable to injected processes on this rootless host.
    return @"/var/jb/var/lib/mks/mks.config";
#endif
}
NSArray<NSString *> *MKSConfigPaths(void) {
    NSMutableArray *paths=[NSMutableArray arrayWithObject:MKSConfigPath()];
#if !TARGET_OS_SIMULATOR
    [paths addObject:@"/var/mobile/Media/mks.config"];
    [paths addObject:@"/var/mobile/Library/Preferences/com.mks.spoof.config"];
    // Only the MKS app's container, rather than every application's Documents folder.
    NSString *base=@"/var/mobile/Containers/Data/Application";
    for (NSString *name in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:base error:NULL] sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *dir=[base stringByAppendingPathComponent:name];
        NSDictionary *meta=[NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
        if ([@[@"com.mks.spoofapp",@"com.mks.spoofer"] containsObject:meta[@"MCMMetadataIdentifier"] ?: @""])
            [paths addObject:[dir stringByAppendingPathComponent:@"Documents/mks.config"]];
    }
#endif
    return paths;
}
static BOOL fail(NSError **error, NSString *text) {
    if (error) *error=[NSError errorWithDomain:@"MKSProfile" code:1 userInfo:@{NSLocalizedDescriptionKey:text}];
    return NO;
}
static BOOL matches(NSString *value, NSString *pattern) {
    return [value rangeOfString:pattern options:NSRegularExpressionSearch].location!=NSNotFound;
}
static NSNumber *uintValue(NSString *text) {
    if (![text isKindOfClass:NSString.class] || !matches(text,@"^(0[xX][0-9a-fA-F]+|[0-9]+)$")) return nil;
    errno=0; char *end=NULL;
    unsigned long long n=strtoull(text.UTF8String,&end,[text.lowercaseString hasPrefix:@"0x"]?16:10);
    return (!errno && end && !*end)?@(n):nil;
}
static NSData *hexData(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return nil;
    NSString *s=[[text stringByReplacingOccurrencesOfString:@":" withString:@""] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    if (!s.length || s.length%2 || !matches(s,@"^[a-fA-F0-9]+$")) return nil;
    NSMutableData *d=[NSMutableData data];
    for (NSUInteger i=0;i<s.length;i+=2) {
        unsigned int x=0; [[NSScanner scannerWithString:[s substringWithRange:NSMakeRange(i,2)]] scanHexInt:&x];
        uint8_t b=(uint8_t)x; [d appendBytes:&b length:1];
    }
    return d;
}
static BOOL luhn(NSString *s) {
    int sum=0; BOOL twice=NO;
    for (NSInteger i=s.length-1;i>=0;i--) { int n=[s characterAtIndex:i]-'0'; if (twice) { n*=2; if(n>9)n-=9; } sum+=n; twice=!twice; }
    return sum%10==0;
}
NSArray<NSString *> *MKSValueKeys(void) {
    return @[@"SerialNumber",@"MLBSerialNumber",@"UniqueDeviceID",@"UniqueChipID",@"DieId",@"ChipID",
        @"InternationalMobileEquipmentIdentity",@"InternationalMobileEquipmentIdentity2",@"MobileEquipmentIdentifier",
        @"WifiAddress",@"EthernetMacAddress",@"BluetoothAddress",@"ProductType",@"ModelNumber",@"HWModelStr",
        @"HardwarePlatform",@"ProductVersion",@"BuildVersion",@"RegionInfo",@"RegionCode"];
}
static BOOL validate(NSDictionary *profile, NSError **error) {
    if (![profile isKindOfClass:NSDictionary.class] || ![profile[@"schemaVersion"] isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)profile[@"schemaVersion"])==CFBooleanGetTypeID() ||
        ![profile[@"schemaVersion"] isEqual:@2]) return fail(error,@"配置 schemaVersion 必须为 2。");
    if (!profile[@"enabled"] || CFGetTypeID((__bridge CFTypeRef)profile[@"enabled"])!=CFBooleanGetTypeID())
        return fail(error,@"enabled 必须为布尔值。");
    for (id key in profile) if (![@[@"schemaVersion",@"enabled",@"name",@"values"] containsObject:key]) return fail(error,@"配置包含未知字段。");
    id name=profile[@"name"];
    if (![name isKindOfClass:NSString.class] || ![name length] || [name length]>128) return fail(error,@"参数名称必须为 1–128 字符。");
    NSDictionary *v=profile[@"values"];
    if (![v isKindOfClass:NSDictionary.class]) return fail(error,@"values 必须为字典。");
    for (id key in v) {
        id value=v[key];
        if (![MKSValueKeys() containsObject:key]) return fail(error,[NSString stringWithFormat:@"未知参数：%@",key]);
        if (![value isKindOfClass:NSString.class] || ![value length] || [value length]>128 ||
            [value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)
            return fail(error,[NSString stringWithFormat:@"%@ 必须为 1–128 字符且不含控制字符。",key]);
        if ([@[@"UniqueChipID",@"DieId",@"ChipID"] containsObject:key] && !uintValue(value)) return fail(error,[key stringByAppendingString:@" 必须为 uint64 十进制或 0x 十六进制。"]);
        if ([key hasSuffix:@"Address"] && !matches(value,@"^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$")) return fail(error,@"MAC 格式错误。");
        if ([key isEqual:@"UniqueDeviceID"] && !matches(value,@"^([0-9a-fA-F]{40}|[0-9a-fA-F]{8}-[0-9a-fA-F]{16})$")) return fail(error,@"UDID 格式错误。");
        if ([key isEqual:@"InternationalMobileEquipmentIdentity"] && (!matches(value,@"^[0-9]{15}$") || !luhn(value))) return fail(error,@"IMEI 长度或 Luhn 校验错误。");
        if ([key isEqual:@"InternationalMobileEquipmentIdentity2"] && !matches(value,@"^[0-9]{14,15}$")) return fail(error,@"IMEI2 长度错误。");
        if ([key isEqual:@"MobileEquipmentIdentifier"] && !matches(value,@"^[a-fA-F0-9]{14}$")) return fail(error,@"MEID 格式错误。");
        if ([key isEqual:@"ProductType"] && !matches(value,@"^(iPhone|iPad|iPod)[0-9]+,[0-9]+$")) return fail(error,@"机型格式错误。");
        if ([key isEqual:@"ProductVersion"] && !matches(value,@"^[0-9]+(\\.[0-9]+){1,2}$")) return fail(error,@"系统版本格式错误。");
    }
    if ([v[@"InternationalMobileEquipmentIdentity2"] length]==14 && v[@"InternationalMobileEquipmentIdentity"] &&
        ![v[@"InternationalMobileEquipmentIdentity"] hasPrefix:v[@"InternationalMobileEquipmentIdentity2"]]) return fail(error,@"旧版 14 位 IMEI2 必须与 IMEI 前缀一致。");
    return YES;
}
NSDictionary *MKSParseLegacy(NSString *line, NSError **error) {
    NSArray *p=[[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsSeparatedByString:@"----"];
    if (p.count!=14) { fail(error,@"旧配置必须恰好包含 14 段，以 ---- 分隔。"); return nil; }
    for (NSString *s in p) if (!s.length || s.length>128) { fail(error,@"旧配置包含空字段或超长字段。"); return nil; }
    if (!matches(p[5],@"^[a-fA-F0-9]{1,16}$") || !matches(p[11],@"^[Tt][a-fA-F0-9]{4}$")) { fail(error,@"旧配置 ECID 或芯片格式错误。"); return nil; }
    NSDictionary *profile=@{@"schemaVersion":@2,@"enabled":@YES,@"name":@"旧版参数",@"values":@{
        @"SerialNumber":p[0],@"InternationalMobileEquipmentIdentity":p[1],@"InternationalMobileEquipmentIdentity2":p[2],
        @"WifiAddress":p[3],@"EthernetMacAddress":p[3],@"BluetoothAddress":p[4],
        @"UniqueChipID":[@"0x" stringByAppendingString:p[5]],@"DieId":[@"0x" stringByAppendingString:p[5]],
        @"UniqueDeviceID":p[6],@"MLBSerialNumber":p[7],@"ProductType":p[8],@"ModelNumber":p[9],
        @"HWModelStr":p[10],@"HardwarePlatform":[p[11] lowercaseString],
        @"ChipID":[@"0x" stringByAppendingString:[p[11] substringFromIndex:1]],@"BuildVersion":p[12],@"ProductVersion":p[13]}};
    return validate(profile,error)?profile:nil;
}
NSDictionary *MKSParseProfile(NSData *data, NSError **error) {
    if (!data.length || data.length>65536) { fail(error,@"配置必须为 1–65536 字节。"); return nil; }
    NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) { fail(error,@"配置不是 UTF-8 文本。"); return nil; }
    if (![[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] hasPrefix:@"{"])
        return MKSParseLegacy(text,error);
    id profile=[NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    return validate(profile,error)?profile:nil;
}
NSData *MKSEncodeProfile(NSDictionary *profile, NSError **error) {
    if (!validate(profile,error)) return nil;
    NSData *data=[NSJSONSerialization dataWithJSONObject:profile options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:error];
    if (data.length>65536) { fail(error,@"配置超过 64 KiB。"); return nil; }
    return data;
}
BOOL MKSWriteProfile(NSDictionary *profile, NSString *path, NSError **error) {
    NSData *data=MKSEncodeProfile(profile,error);
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:error]) return NO;
    // App/TrollStore and injected system processes must observe the same readable file.
    if (chmod(path.fileSystemRepresentation,0644)!=0) return fail(error,@"配置已写入，但设置读取权限失败。");
    NSDictionary *readBack=MKSParseProfile([NSData dataWithContentsOfFile:path],error);
    return [readBack isEqual:profile] ?: fail(error,@"配置回读与写入不一致。");
}
static NSString *pick(NSString *chars, NSUInteger count) {
    NSMutableString *s=[NSMutableString string];
    for (NSUInteger i=0;i<count;i++) [s appendFormat:@"%C",[chars characterAtIndex:arc4random_uniform((uint32_t)chars.length)]];
    return s;
}
static NSString *mac(void) {
    NSMutableArray *bytes=[NSMutableArray arrayWithObject:@"02"];
    for (int i=0;i<5;i++) [bytes addObject:pick(@"0123456789abcdef",2)];
    return [bytes componentsJoinedByString:@":"];
}
NSDictionary *MKSGenerateProfile(void) {
    // Keep a real model/board/SoC and OS/build pair; random identifiers remain local test data.
    NSArray *devices=@[@[@"iPhone14,7",@"D27AP",@"t8110",@"0x8110"],@[@"iPhone15,2",@"D73AP",@"t8120",@"0x8120"]];
    NSArray *d=devices[arc4random_uniform((uint32_t)devices.count)];
    NSString *body=pick(@"0123456789",14), *imei=nil;
    for(int i=0;i<10;i++) { NSString *s=[body stringByAppendingFormat:@"%d",i]; if(luhn(s)) { imei=s; break; } }
    NSString *sn=pick(@"ABCDEFGHJKLMNPQRSTUVWXYZ123456789",10), *wifi=mac();
    NSString *ecid=[@"0x" stringByAppendingString:pick(@"0123456789ABCDEF",16)];
    return @{@"schemaVersion":@2,@"enabled":@YES,@"name":[@"随机参数 " stringByAppendingString:sn],@"values":@{
        @"SerialNumber":sn,@"MLBSerialNumber":pick(@"ABCDEFGHJKLMNPQRSTUVWXYZ123456789",17),
        @"InternationalMobileEquipmentIdentity":imei ?: @"000000000000000",@"InternationalMobileEquipmentIdentity2":body,
        @"MobileEquipmentIdentifier":pick(@"0123456789ABCDEF",14),
        @"WifiAddress":wifi,@"EthernetMacAddress":wifi,@"BluetoothAddress":mac(),@"UniqueChipID":ecid,@"DieId":ecid,
        @"UniqueDeviceID":pick(@"0123456789abcdef",40),@"ProductType":d[0],@"HWModelStr":d[1],@"HardwarePlatform":d[2],@"ChipID":d[3],
        @"ModelNumber":[NSString stringWithFormat:@"M%@LL/A",pick(@"ABCDEFGHJKLMNPQRSTUVWXYZ123456789",4)],
        @"RegionInfo":@"LL/A",@"RegionCode":@"LL",@"ProductVersion":@"16.3.1",@"BuildVersion":@"20D67"}};
}
id MKSMGValue(NSDictionary *p, NSString *key) {
    if (![p[@"enabled"] boolValue]) return nil;
    NSDictionary *v=p[@"values"];
    if([key isEqual:@"re6Zb+zwFKJNlkQTUeT+/w"]) return v[@"UniqueDeviceID"];
    if([key isEqual:@"h63QSdBCiT/z0WU6rdQv6Q"]) return v[@"RegionCode"];
    if ([@[@"UniqueChipID",@"DieId",@"ChipID"] containsObject:key]) return uintValue(v[key]);
    if ([key isEqual:@"UniqueDeviceIDData"]) return hexData(v[@"UniqueDeviceID"]);
    if ([key isEqual:@"HardwareModel"]) return v[@"HWModelStr"];
    if ([key isEqual:@"HumanReadableProductVersionString"]) return v[@"ProductVersion"];
    // ProductName is the OS product (for example "iPhone OS"), not the
    // hardware family. Preserve its native value through every MG getter.
    return v[key];
}
NSString *MKSProfileUUID(NSDictionary *p) {
    NSData *bytes=hexData(MKSMGValue(p,@"UniqueDeviceID"));
    if (!bytes.length) return nil;
    uint8_t uuid[16]={0}; memcpy(uuid,bytes.bytes,MIN(bytes.length,sizeof(uuid)));
    return [[NSUUID alloc] initWithUUIDBytes:uuid].UUIDString;
}
id MKSRegistryValue(NSDictionary *p, NSString *key, id original) {
    if (!original) return nil; // Do not create a property on an unrelated registry entry.
    if([key isEqual:@"udid-version"]) {
        NSString *udid=MKSMGValue(p,@"UniqueDeviceID");
        if(!udid) return nil;
        uint32_t version=CFSwapInt32HostToLittle(udid.length==40?1:2);
        if([original isKindOfClass:NSData.class]) return [NSData dataWithBytes:&version length:4];
        if([original isKindOfClass:NSNumber.class]) return @(CFSwapInt32LittleToHost(version));
        return nil;
    }
    if ([key isEqual:@"IOPlatformUUID"] && [original isKindOfClass:NSString.class]) return MKSProfileUUID(p);
    NSDictionary *map=@{@"IOPlatformSerialNumber":@"SerialNumber",@"serial-number":@"SerialNumber",
        @"unique-chip-id":@"UniqueChipID",@"die-id":@"DieId",@"board-id":@"HWModelStr",
        @"mac-address-wifi0":@"WifiAddress",@"mac-address-bluetooth0":@"BluetoothAddress",
        @"local-mac-address":@"BluetoothAddress",@"IOMACAddress":@"WifiAddress"};
    NSString *field=map[key]; if (!field) return nil;
    id value=MKSMGValue(p,field); if (!value) return nil;
    if ([original isKindOfClass:NSData.class]) {
        if ([value isKindOfClass:NSNumber.class]) { uint64_t n=CFSwapInt64HostToLittle([value unsignedLongLongValue]); return [NSData dataWithBytes:&n length:8]; }
        if ([field hasSuffix:@"Address"]) return hexData(value);
        NSMutableData *d=[[value dataUsingEncoding:NSUTF8StringEncoding] mutableCopy]; uint8_t zero=0; [d appendBytes:&zero length:1]; return d;
    }
    if ([original isKindOfClass:NSNumber.class] && [value isKindOfClass:NSNumber.class]) return value;
    if ([original isKindOfClass:NSString.class] && [value isKindOfClass:NSString.class]) return value;
    return nil;
}
int MKSStringSysctl(NSString *value, void *output, size_t *length) {
    if (!length) { errno=EFAULT; return -1; }
    size_t required=strlen(value.UTF8String)+1, capacity=*length;
    if (!output) { *length=required; return 0; }
    // Darwin's sysctl_handle_string rejects a short buffer without a partial copy.
    if (capacity<required) { *length=0; errno=ENOMEM; return -1; }
    memcpy(output,value.UTF8String,required); *length=required;
    return 0;
}
@implementation MKSProfileStore {
    NSArray<NSString *> *_paths;
    NSLock *_lock;
    NSString *_fingerprint;
    NSDictionary *_cached;
}
- (instancetype)initWithPaths:(NSArray<NSString *> *)paths {
    if ((self=[super init])) { _paths=[paths copy]; _lock=[NSLock new]; }
    return self;
}
- (NSDictionary *)snapshot {
    [_lock lock];
    @try {
        for (NSString *path in _paths) {
            struct stat st;
            if (stat(path.fileSystemRepresentation,&st)!=0) {
                if (errno!=ENOENT && errno!=ENOTDIR) { _cached=nil; _fingerprint=nil; return nil; }
                continue;
            }
            // Path, inode, size, mtime and ctime prevent same-second/profile-path stale caches.
            NSString *fp=[NSString stringWithFormat:@"%@:%llu:%llu:%lld:%ld:%lld:%ld",path,
                (unsigned long long)st.st_ino,(unsigned long long)st.st_size,(long long)st.st_mtimespec.tv_sec,
                st.st_mtimespec.tv_nsec,(long long)st.st_ctimespec.tv_sec,st.st_ctimespec.tv_nsec];
            if (![_fingerprint isEqual:fp]) {
                _fingerprint=fp;
                _cached=nil;
                if (S_ISREG(st.st_mode) && st.st_size>0 && st.st_size<=65536) {
                    NSData *data=[NSData dataWithContentsOfFile:path];
                    if (data) _cached=MKSParseProfile(data,NULL);
                }
            }
            // An explicit OFF/invalid primary file is authoritative; never revive a stale fallback.
            return _cached;
        }
        _cached=nil; _fingerprint=nil; return nil;
    } @finally { [_lock unlock]; }
}
@end
