#define MKS_UNIT_TEST 1
#import "../tweak/mks.m"
#include <errno.h>
#include <stdatomic.h>

static int checks, failures;
#define CHECK(condition,label) do { checks++; if(!(condition)) { failures++; fprintf(stderr,"FAIL %s\n",label); } } while(0)
static CFStringRef originalString(CFStringRef key) { return CFEqual(key,CFSTR("ProductName"))?CFSTR("iPhone OS"):CFSTR("ORIGINAL"); }
static uintptr_t receivedContext;
static int internalOriginalMode;
static CFTypeRef originalAnswer(CFStringRef key) {
    if(key && CFEqual(key,CFSTR("ProductName"))) return CFRetain(CFSTR("iPhone OS"));
    if(key && CFEqual(key,CFSTR("BasebandPostponementStatusBlob"))) return CFBridgingRetain(@{
        @"InternationalMobileEquipmentIdentity":@"original-imei",@"MobileEquipmentIdentifier":@"original-meid",
        @"kCTPostponementInfoUniqueID":@"original-id",@"Other":@"keep"});
    return CFRetain(CFSTR("ORIGINAL"));
}
static CFTypeRef originalInternal(CFStringRef key,uint32_t *answerType) {
    receivedContext=(uintptr_t)answerType;
    if(internalOriginalMode==2) { if(answerType) *answerType=0;return NULL; }
    if(internalOriginalMode==1) { if(answerType) *answerType=6;return CFBridgingRetain(@321); }
    id value=nil;uint32_t type=9;
    if(CFEqual(key,CFSTR("UniqueChipID"))) { value=@123;type=6; }
    else if(CFEqual(key,CFSTR("UniqueDeviceIDData"))) { value=[NSData dataWithBytes:"x" length:1];type=10; }
    else if(CFEqual(key,CFSTR("BasebandPostponementStatusBlob"))) type=2;
    if(answerType) *answerType=type;
    return value?CFBridgingRetain(value):originalAnswer(key);
}
static CFTypeRef originalProperty(io_registry_entry_t e,CFStringRef key,CFAllocatorRef a,IOOptionBits o) {
    (void)a; (void)o;
    if(e==0) return NULL;
    if(CFEqual(key,CFSTR("unique-chip-id")) || CFEqual(key,CFSTR("IOMACAddress")) || CFEqual(key,CFSTR("board-id")))
        return CFBridgingRetain([NSMutableData dataWithLength:8]);
    return CFRetain(CFSTR("ORIGINAL"));
}
static CFTypeRef originalSearch(io_registry_entry_t e,const char *plane,CFStringRef key,CFAllocatorRef a,IOOptionBits o) {
    (void)plane; return originalProperty(e,key,a,o);
}
static CFDictionaryRef originalVersion(void) { return CFBridgingRetain(@{@"ProductVersion":@"1.0",@"ProductBuildVersion":@"BASE",@"Other":@"keep"}); }
static int originalSysctl(const char *n,void *o,size_t *l,void *w,size_t z) { (void)n;(void)o;(void)l;(void)w;(void)z;return 23; }
static int originalMib(int *n,u_int c,void *o,size_t *l,void *w,size_t z) { (void)n;(void)c;return originalSysctl(NULL,o,l,w,z); }
static id originalID(id obj,SEL sel) { (void)obj;(void)sel;return [[NSUUID alloc] initWithUUIDString:@"12345678-1234-1234-1234-123456789ABC"]; }
static id deniedID(id obj,SEL sel) { (void)obj;(void)sel;return [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000000"]; }
@interface MockEquipment : NSObject <NSCopying>
@property(copy) NSString *IMEI;
@property(copy) NSString *MEID;
@end
@implementation MockEquipment
- (id)copyWithZone:(NSZone *)zone { MockEquipment *other=[[MockEquipment allocWithZone:zone] init];other.IMEI=self.IMEI;other.MEID=self.MEID;return other; }
@end
static NSDictionary *equipmentOriginal;
static id originalEquipment(id obj,SEL sel) { (void)obj;(void)sel;return equipmentOriginal; }
static id originalBuild(id obj,SEL sel) { (void)obj;(void)sel;return @"ORIGINAL-BUILD"; }
static NSMutableDictionary *updated(NSDictionary *p,NSString *serial,NSString *udid) {
    NSMutableDictionary *q=[p mutableCopy],*v=[p[@"values"] mutableCopy];
    v[@"SerialNumber"]=serial;v[@"UniqueDeviceID"]=udid;q[@"values"]=v;return q;
}
int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc!=3) return 2;
        CHECK([MKSConfigPath() isEqual:@"/var/jb/var/lib/mks/mks.config"],"primary profile is inside sandbox-readable jailbreak root");
        CHECK([MKSConfigPaths().firstObject isEqual:MKSConfigPath()],"app and tweak share authoritative primary path");
        CHECK([MKSConfigPaths() containsObject:@"/var/mobile/Media/mks.config"],"legacy media profile remains a migration fallback");
        NSString *fixture=[NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:NULL];
        NSDictionary *a=MKSParseLegacy(fixture,NULL);
        CHECK(a!=nil,"legacy parse");
        CHECK([MKSMGValue(a,@"WifiAddress") isEqual:@"02:11:22:33:44:55"],"wifi alias");
        CHECK([MKSMGValue(a,@"HWModelStr") isEqual:@"D73AP"],"board key");
        CHECK([MKSMGValue(a,@"HardwareModel") isEqual:@"D73AP"],"legacy board alias");
        CHECK([MKSMGValue(a,@"MLBSerialNumber") isEqual:@"BOARD123456789ABC"],"MLB mapping");
        CHECK([MKSMGValue(a,@"UniqueChipID") unsignedLongLongValue]==0x123456789ABCULL,"ECID uint64");
        CHECK([MKSMGValue(a,@"ChipID") isKindOfClass:NSNumber.class],"chip type");
        CHECK([MKSMGValue(a,@"ChipID") unsignedLongLongValue]==0x8120,"chip value");
        CHECK([MKSMGValue(a,@"UniqueDeviceIDData") length]==20,"UDID bytes");
        CHECK([MKSProfileUUID(a) isEqual:@"00112233-4455-6677-8899-AABBCCDDEEFF"],"initial UUID");
        CHECK(MKSMGValue(a,@"Unknown")==nil,"unknown passthrough");
        CHECK(MKSMGValue(a,@"ProductName")==nil,"ProductName is an OS name, not the device family");
        CHECK([MKSMGValue(a,@"re6Zb+zwFKJNlkQTUeT+/w") isEqual:MKSMGValue(a,@"UniqueDeviceID")],"observed hashed UDID alias");
        uint32_t forward[]={0xd2800001,0x14000004};
        CHECK(MKSBranchTarget(forward,8,0x1000)==0x1014,"MOV X1 plus B thunk");
        uint32_t backward[]={0x52800001,0x17fffffe};
        CHECK(MKSBranchTarget(backward,8,0x1000)==0xffc,"MOV W1 plus backward B thunk");
        uint32_t direct[]={0x14000004};
        CHECK(MKSBranchTarget(direct,4,0x1000)==0x1010,"direct B thunk");
        uint32_t bl[]={0x94000004};CHECK(MKSBranchTarget(bl,4,0x1000)==0,"BL is not a forwarding thunk");
        uint32_t unrelated[]={0xd503201f,0x14000004};CHECK(MKSBranchTarget(unrelated,8,0x1000)==0,"unknown prologue passthrough");
        CHECK(MKSBranchTarget(forward,4,0x1000)==0,"truncated MOV thunk");
        uint32_t underflow[]={0x17fffffc};CHECK(MKSBranchTarget(underflow,4,4)==0,"branch address underflow");
        CHECK(MKSParseLegacy([fixture stringByReplacingOccurrencesOfString:@"----T8120" withString:@"----"],NULL)==nil,"empty legacy field");
        CHECK(MKSParseLegacy([fixture stringByAppendingString:@"----extra"],NULL)==nil,"extra legacy field");
        CHECK(MKSParseProfile([@"{broken" dataUsingEncoding:NSUTF8StringEncoding],NULL)==nil,"bad JSON");
        CHECK(MKSParseProfile([NSMutableData dataWithLength:65537],NULL)==nil,"oversized input");
        NSMutableDictionary *bad=[a mutableCopy];bad[@"enabled"]=@"yes";
        CHECK(MKSEncodeProfile(bad,NULL)==nil,"typed enabled");
        bad=[a mutableCopy];bad[@"values"]=@{@"ChipID":@"18446744073709551616"};
        CHECK(MKSEncodeProfile(bad,NULL)==nil,"uint64 overflow");
        bad=[a mutableCopy];bad[@"values"]=@{@"UniqueChipID":@"0xFFFFFFFFFFFFFFFF"};
        CHECK([MKSMGValue(bad,@"UniqueChipID") unsignedLongLongValue]==UINT64_MAX,"full uint64");
        for(int i=0;i<100;i++) {
            NSDictionary *p=MKSGenerateProfile();
            CHECK(MKSParseProfile(MKSEncodeProfile(p,NULL),NULL)!=nil,"generated validation");
            NSDictionary *v=p[@"values"];
            CHECK(MKSProfileHTMLRuleErrors(p).count==0,"generated profile passes HTML certificate rules");
            CHECK(MKSParseLegacy(MKSProfileHTMLParameters(p),NULL)!=nil,"HTML export round trips through legacy parser");
            CHECK([v[@"ProductType"] isEqual:@"iPhone16,2"],"HTML default model mapping");
            CHECK([v[@"SerialNumber"] isEqual:v[@"MLBSerialNumber"]],"HTML repeated serial fields");
            CHECK([v[@"InternationalMobileEquipmentIdentity2"] isEqual:[v[@"InternationalMobileEquipmentIdentity"] substringToIndex:14]],"HTML IMEI2 prefix");
            CHECK([[v[@"HardwarePlatform"] uppercaseString] isEqual:[@"T" stringByAppendingString:[v[@"ChipID"] substringFromIndex:2]]],"HTML chip mapping");
            CHECK([v[@"RegionInfo"] isEqual:@"LL/A"] && [v[@"RegionCode"] isEqual:@"LL"],"HTML default region mapping");
            CHECK(v[@"MobileEquipmentIdentifier"]==nil,"HTML parameter set does not add a MEID field");
        }
        NSMutableDictionary *badHTML=[MKSGenerateProfile() mutableCopy];
        NSMutableDictionary *badValues=[badHTML[@"values"] mutableCopy];
        badValues[@"HardwarePlatform"]=@"t9398";badValues[@"ChipID"]=@"0x9398";badHTML[@"values"]=badValues;
        CHECK([MKSProfileHTMLRuleErrors(badHTML) containsObject:@"chip_format"],"HTML rejects T9 chip output");
        badHTML=[MKSGenerateProfile() mutableCopy];badValues=[badHTML[@"values"] mutableCopy];
        badValues[@"MLBSerialNumber"]=@"DIFFERENT123";badHTML[@"values"]=badValues;
        CHECK([MKSProfileHTMLRuleErrors(badHTML) containsObject:@"serial_repeat"],"HTML repeated serial rule");
        badHTML=[MKSGenerateProfile() mutableCopy];badValues=[badHTML[@"values"] mutableCopy];
        badValues[@"ProductType"]=@"iPhone14,7";badHTML[@"values"]=badValues;
        CHECK([MKSProfileHTMLRuleErrors(badHTML) containsObject:@"product_type"],"HTML model list");
        badHTML=[MKSGenerateProfile() mutableCopy];badValues=[badHTML[@"values"] mutableCopy];
        badValues[@"HWModelStr"]=@"D73AP";badHTML[@"values"]=badValues;
        CHECK(![MKSProfileHTMLRuleErrors(badHTML) containsObject:@"board_format"],"HTML accepts any two-digit board");
        badValues[@"HWModelStr"]=@"D7AP";
        CHECK([MKSProfileHTMLRuleErrors(badHTML) containsObject:@"board_format"],"HTML board format");
        NSString *dir=@(argv[2]);[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *path=[dir stringByAppendingPathComponent:@"active.json"], *fallback=[dir stringByAppendingPathComponent:@"fallback.json"];
        [NSFileManager.defaultManager removeItemAtPath:path error:NULL];[NSFileManager.defaultManager removeItemAtPath:fallback error:NULL];
        store=[[MKSProfileStore alloc] initWithPaths:@[path,fallback]];
        CHECK([store snapshot]==nil,"missing state");
        CHECK(MKSWriteProfile(a,path,NULL),"atomic save readback");
        CHECK([[[NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL] objectForKey:NSFilePosixPermissions] unsignedIntValue]==0644,"shared read permissions");
        orig_MGGetStringAnswer=originalString;orig_MGCopyAnswer=originalAnswer;
        CHECK(CFEqual(my_MGGetStringAnswer(CFSTR("ProductName")),CFSTR("iPhone OS")),"string getter preserves native OS ProductName");
        orig_MGCopyAnswerInternal=originalInternal;orig_equipment=originalEquipment;orig_deviceBuild=originalBuild;
        orig_IORegistryEntryCreateCFProperty=originalProperty;orig_IORegistryEntrySearchCFProperty=originalSearch;
        orig_CFCopySystemVersionDictionary=originalVersion;
        orig_sysctlbyname=originalSysctl;orig_sysctl=originalMib;orig_idfv=originalID;orig_idfa=originalID;
        CFTypeRef nativeOSName=my_MGCopyAnswer(CFSTR("ProductName"));
        CHECK(CFEqual(nativeOSName,CFSTR("iPhone OS")),"Copy getter preserves native OS ProductName");CFRelease(nativeOSName);
        CFStringRef borrowed=my_MGGetStringAnswer(CFSTR("SerialNumber"));
        CHECK(CFEqual(borrowed,CFSTR("ABCDEFGHJK")),"Get string");
        // A long UDID is heap-backed; short strings may be immortal tagged pointers.
        CFStringRef firstProduct=my_MGGetStringAnswer(CFSTR("UniqueDeviceID"));
        CFIndex refsBefore=CFGetRetainCount(firstProduct);
        CFStringRef nextProduct=my_MGGetStringAnswer(CFSTR("UniqueDeviceID"));
        BOOL ownsString=CFGetRetainCount(firstProduct)==refsBefore+1;
        CHECK(ownsString,"MGGetStringAnswer gives each caller its own retained reference");
        if(ownsString) { CFRelease(nextProduct);CFRelease(firstProduct); }
        if(ownsString) {
            BOOL releaseLoopOK=YES;
            for(int i=0;i<10000;i++) {
                @autoreleasepool {
                    CFStringRef answer=my_MGGetStringAnswer(CFSTR("UniqueDeviceID"));
                    releaseLoopOK&=answer && CFStringGetLength(answer)==40;
                    if(answer) CFRelease(answer);
                }
            }
            CHECK(releaseLoopOK,"MG string repeated caller release preserves cached profile");
        }
        CHECK(CFEqual(my_MGGetStringAnswer(CFSTR("ChipID")),CFSTR("ORIGINAL")),"string API does not return number");
        CFTypeRef copied=my_MGCopyAnswer(CFSTR("UniqueChipID"));
        CHECK(CFGetTypeID(copied)==CFNumberGetTypeID(),"Copy numeric type");CFRelease(copied);
        copied=my_MGCopyAnswer(CFSTR("UniqueDeviceIDData"));CHECK(CFGetTypeID(copied)==CFDataGetTypeID(),"Copy data type");CFRelease(copied);
        uint32_t metadata[2]={0,0xcafebabe};
        copied=my_MGCopyAnswerInternal(CFSTR("ProductName"),metadata);
        CHECK(CFEqual(copied,CFSTR("iPhone OS")) && metadata[0]==9,"internal MG preserves native OS ProductName and type");CFRelease(copied);
        copied=my_MGCopyAnswerInternal(CFSTR("unknown"),metadata);
        CHECK(receivedContext==(uintptr_t)metadata && metadata[0]==9 && CFEqual(copied,CFSTR("ORIGINAL")),"internal MG preserves second argument");CFRelease(copied);
        metadata[0]=0;
        copied=my_MGCopyAnswerInternal(CFSTR("SerialNumber"),metadata);
        CHECK(CFEqual(copied,CFSTR("ABCDEFGHJK")),"internal MG scalar mapping");CFRelease(copied);
        CHECK(metadata[0]==9,"internal MG replacement must fill string type output");
        metadata[0]=0;
        copied=my_MGCopyAnswerInternal(CFSTR("UniqueChipID"),metadata);
        CHECK(metadata[0]==6,"internal MG replacement must fill numeric type output for typed getter");
        CHECK(CFGetTypeID(copied)==CFNumberGetTypeID(),"internal MG numeric result matches metadata");
        CHECK([(__bridge NSNumber *)copied unsignedLongLongValue]==0x123456789ABCULL,"internal MG numeric replacement value");CFRelease(copied);
        metadata[0]=0;
        copied=my_MGCopyAnswerInternal(CFSTR("UniqueDeviceIDData"),metadata);
        CHECK(metadata[0]==10,"internal MG replacement must fill data type output");CFRelease(copied);
        CHECK(metadata[1]==0xcafebabe,"internal MG type output is 32 bits, not CFTypeID width");
        copied=my_MGCopyAnswerInternal(CFSTR("SerialNumber"),NULL);
        CHECK(CFEqual(copied,CFSTR("ABCDEFGHJK")),"internal MG exported path allows null type output");CFRelease(copied);
        internalOriginalMode=1;
        copied=my_MGCopyAnswerInternal(CFSTR("SerialNumber"),metadata);
        CHECK(metadata[0]==6 && [(__bridge id)copied isEqual:@321],"internal MG preserves incompatible native type and value");CFRelease(copied);
        internalOriginalMode=2;
        copied=my_MGCopyAnswerInternal(CFSTR("SerialNumber"),metadata);
        CHECK(copied==NULL && metadata[0]==0,"internal MG preserves unsupported native answer");
        internalOriginalMode=0;
        copied=my_MGCopyAnswerInternal(CFSTR("BasebandPostponementStatusBlob"),metadata);
        CHECK(metadata[0]==2 && CFGetTypeID(copied)==CFDictionaryGetTypeID(),"internal MG baseband dictionary preserves metadata");CFRelease(copied);
        copied=my_MGCopyAnswer(CFSTR("BasebandPostponementStatusBlob"));
        CHECK([((__bridge NSDictionary *)copied)[@"InternationalMobileEquipmentIdentity"] isEqual:@"490154203237518"],"baseband dictionary IMEI");
        CHECK([((__bridge NSDictionary *)copied)[@"Other"] isEqual:@"keep"],"baseband unrelated fields preserved");CFRelease(copied);
        MockEquipment *equipment=[MockEquipment new];equipment.IMEI=@"real-imei";equipment.MEID=@"real-meid";
        equipmentOriginal=@{@"primary":equipment};
        NSDictionary *patched=my_equipment(nil,NULL);
        CHECK([((MockEquipment *)patched[@"primary"]).IMEI isEqual:@"490154203237518"],"CoreTelephony setter mapping");
        CHECK([equipment.IMEI isEqual:@"real-imei"],"CoreTelephony cached original untouched");
        CHECK([my_deviceBuild(nil,NULL) isEqual:@"20D67"],"AADeviceInfo buildVersion");
        NSData *udidVersion=MKSRegistryValue(a,@"udid-version",[NSMutableData dataWithLength:4]);uint32_t uv=0;[udidVersion getBytes:&uv length:4];
        CHECK(CFSwapInt32LittleToHost(uv)==1,"registry UDID version bytes");
        copied=my_IORegistryEntryCreateCFProperty(1,CFSTR("unique-chip-id"),NULL,0);
        uint64_t ecid=0;[(__bridge NSData *)copied getBytes:&ecid length:8];
        CHECK(CFSwapInt64LittleToHost(ecid)==0x123456789ABCULL,"IO data little endian");CFRelease(copied);
        copied=my_IORegistryEntrySearchCFProperty(1,"IODeviceTree",CFSTR("IOMACAddress"),NULL,0);
        CHECK([(__bridge NSData *)copied length]==6,"IO search MAC data");CFRelease(copied);
        CHECK(my_IORegistryEntrySearchCFProperty(0,"IODeviceTree",CFSTR("IOMACAddress"),NULL,0)==NULL,"missing registry property");
        copied=my_IORegistryEntryCreateCFProperty(1,CFSTR("unknown"),NULL,0);
        CHECK(CFEqual(copied,CFSTR("ORIGINAL")),"unknown IO passthrough");CFRelease(copied);
        CFDictionaryRef version=my_CFCopySystemVersionDictionary();
        CHECK([((__bridge NSDictionary *)version)[@"ProductVersion"] isEqual:@"16.3.1"],"version dictionary");
        CHECK([((__bridge NSDictionary *)version)[@"Other"] isEqual:@"keep"],"version unrelated fields");CFRelease(version);
        size_t len=0;CHECK(my_sysctlbyname("hw.machine",NULL,&len,NULL,0)==0 && len==11,"sysctl size query");
        char buf[64]={0};len=2;errno=0;
        CHECK(my_sysctlbyname("hw.machine",buf,&len,NULL,0)==-1 && errno==ENOMEM && len==0 && buf[0]==0,"sysctl short buffer");
        len=sizeof(buf);CHECK(my_sysctlbyname("hw.machine",buf,&len,NULL,0)==0 && !strcmp(buf,"iPhone15,2"),"sysctl read");
        CHECK(my_sysctlbyname("hw.machine",buf,&len,buf,1)==23,"sysctl write passthrough");
        CHECK(my_sysctlbyname("unknown",buf,&len,NULL,0)==23,"sysctl unknown passthrough");
        int mib[]={CTL_HW,HW_MODEL};len=sizeof(buf);
        CHECK(my_sysctl(mib,2,buf,&len,NULL,0)==0 && !strcmp(buf,"D73AP"),"sysctl MIB");
        NSString *uuidA=[my_idfv(nil,NULL) UUIDString];
        NSDictionary *b=updated(a,@"KJHGFEDCBA",@"ffeeddccbbaa99887766554433221100ffeeddcc");
        CHECK(MKSWriteProfile(b,path,NULL),"same-second update");
        CHECK([MKSMGValue([store snapshot],@"SerialNumber") isEqual:@"KJHGFEDCBA"],"same-second cache refresh");
        CHECK(![[my_idfv(nil,NULL) UUIDString] isEqual:uuidA],"IDFV refresh");
        CHECK(CFEqual(borrowed,CFSTR("ABCDEFGHJK")),"retained Get survives update");CFRelease(borrowed);
        orig_idfa=deniedID;CHECK([[my_idfa(nil,NULL) UUIDString] isEqual:@"00000000-0000-0000-0000-000000000000"],"ATT denied passthrough");
        // Copy ownership and reloads: caller always releases exactly once.
        for(int i=0;i<10000;i++) { @autoreleasepool { CFTypeRef r=my_MGCopyAnswer(CFSTR("SerialNumber")); if(!r) failures++;else CFRelease(r); } }
        CHECK(YES,"Copy release loop completed");
        __block int threadErrors=0;
        dispatch_group_t group=dispatch_group_create();
        for(int thread=0;thread<4;thread++) dispatch_group_async(group,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            for(int i=0;i<1000;i++) { @autoreleasepool {
                NSDictionary *p=[store snapshot];NSString *s=MKSMGValue(p,@"SerialNumber");NSString *u=MKSProfileUUID(p);
                if(!([s isEqual:@"ABCDEFGHJK"] && [u isEqual:@"00112233-4455-6677-8899-AABBCCDDEEFF"]) &&
                   !([s isEqual:@"KJHGFEDCBA"] && [u isEqual:@"FFEEDDCC-BBAA-9988-7766-554433221100"])) __atomic_fetch_add(&threadErrors,1,__ATOMIC_RELAXED);
            } }
        });
        for(int i=0;i<100;i++) CHECK(MKSWriteProfile(i%2?a:b,path,NULL),"concurrent atomic update");
        dispatch_group_wait(group,DISPATCH_TIME_FOREVER);
        CHECK(threadErrors==0,"concurrent coherent snapshots");
        CHECK(MKSWriteProfile(b,fallback,NULL),"fallback save");
        NSDictionary *off=@{@"schemaVersion":@2,@"enabled":@NO,@"name":@"off",@"values":@{}};
        CHECK(MKSWriteProfile(off,path,NULL),"disable save");
        CHECK(MKSMGValue([store snapshot],@"SerialNumber")==nil,"OFF blocks stale fallback");
        copied=my_MGCopyAnswer(CFSTR("SerialNumber"));CHECK(CFEqual(copied,CFSTR("ORIGINAL")),"disabled Copy restores original");CFRelease(copied);
        CHECK([[my_idfv(nil,NULL) UUIDString] isEqual:[originalID(nil,NULL) UUIDString]],"disabled IDFV restores original");
        CHECK(my_equipment(nil,NULL)==equipmentOriginal && [equipment.IMEI isEqual:@"real-imei"],"disabled CoreTelephony restores original");
        CHECK([my_deviceBuild(nil,NULL) isEqual:@"ORIGINAL-BUILD"],"disabled AADeviceInfo restores original");
        [@"{invalid" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        CHECK([store snapshot]==nil,"invalid primary blocks fallback");
        [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
        CHECK([MKSMGValue([store snapshot],@"SerialNumber") isEqual:@"KJHGFEDCBA"],"legacy fallback when primary missing");
        [NSFileManager.defaultManager removeItemAtPath:fallback error:NULL];CHECK([store snapshot]==nil,"delete clears cache");
        printf("MODIFIED checks=%d failures=%d; typed fields, reload, ownership, sysctl, concurrency, restore verified\n",checks,failures);
        return failures?1:0;
    }
}
