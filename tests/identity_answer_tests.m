#define MKS_UNIT_TEST 1
#import "../tweak/mks.m"

static int checks,failures,nativeCalls,searchCalls;
#define CHECK(value) do { checks++;if(!(value)) { failures++;fprintf(stderr,"FAIL line=%d %s\n",__LINE__,#value); } } while(0)
static CFTypeRef missingAnswer(CFStringRef key,uint32_t *type) {
    nativeCalls++;(void)key;if(type) *type=0;return NULL;
}
static CFTypeRef incompatibleAnswer(CFStringRef key,uint32_t *type) {
    nativeCalls++;(void)key;if(type) *type=6;return CFBridgingRetain(@123);
}
static CFTypeRef missingSearch(io_registry_entry_t entry,const char *plane,CFStringRef key,CFAllocatorRef allocator,IOOptionBits options) {
    (void)entry;(void)plane;(void)key;(void)allocator;(void)options;searchCalls++;return NULL;
}
int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc!=2)return 2;
        NSString *path=@(argv[1]);
        NSDictionary *profile=MKSGenerateProfile();
#if defined(MKS_ROOTHIDE)
        CHECK([MKSMGValue(profile,@"ModelNumber") isEqual:[profile[@"values"][@"ModelNumber"] substringToIndex:5]]);
        CHECK([MKSMGValue(profile,@"MobileEquipmentIdentifier") isEqual:profile[@"values"][@"InternationalMobileEquipmentIdentity2"]]);
        CHECK(MKSMGValue(profile,@"InternationalMobileEquipmentIdentity2")==nil);
        CHECK(MKSMGValue(profile,@"HardwareModel")==nil);
        NSDictionary *legacy=MKSParseLegacy(MKSProfileHTMLParameters(profile),NULL);
        CHECK([MKSMGValue(legacy,@"RegionInfo") isEqual:@"LL/A"]);
        CHECK([MKSMGValue(legacy,@"RegionCode") isEqual:@"LL"]);
        NSMutableDictionary *explicitProfile=[profile mutableCopy],*explicitValues=[profile[@"values"] mutableCopy];
        explicitValues[@"MobileEquipmentIdentifier"]=@"A123456789ABCD";explicitProfile[@"values"]=explicitValues;
        CHECK([MKSMGValue(explicitProfile,@"MobileEquipmentIdentifier") isEqual:@"A123456789ABCD"]);
#else
        CHECK([MKSMGValue(profile,@"ModelNumber") isEqual:profile[@"values"][@"ModelNumber"]]);
        CHECK(MKSMGValue(profile,@"MobileEquipmentIdentifier")==nil);
#endif
        CHECK(MKSWriteProfile(profile,path,NULL));
        store=[[MKSProfileStore alloc] initWithPaths:@[path]];
        orig_MGCopyAnswerInternal=missingAnswer;
        for(NSString *key in @[@"SerialNumber",@"MLBSerialNumber",@"UniqueChipID",@"UniqueDeviceIDData",
                              @"InternationalMobileEquipmentIdentity",@"WifiAddress",@"MobileEquipmentIdentifier",@"ModelNumber"]) {
            uint32_t types[]={0xffffffff,0xcafebabe};nativeCalls=0;
            CFTypeRef answer=my_MGCopyAnswerInternal((__bridge CFStringRef)key,&types[0]);
            CHECK(types[1]==0xcafebabe);
#if defined(MKS_ROOTHIDE)
            id expected=MKSMGValue(profile,key);
            CHECK(answer && [(__bridge id)answer isEqual:expected]);
            CHECK(types[0]==([expected isKindOfClass:NSNumber.class]?6:[expected isKindOfClass:NSData.class]?10:9));
            CHECK(nativeCalls==0);
            if(answer)CFRelease(answer);
            answer=my_MGCopyAnswerInternal((__bridge CFStringRef)key,NULL);
            CHECK(answer && [(__bridge id)answer isEqual:expected]);
            if(answer)CFRelease(answer);
#else
            CHECK(answer==NULL && types[0]==0 && nativeCalls==1);
#endif
        }
        uint32_t type=99;
        CHECK(my_MGCopyAnswerInternal(CFSTR("UnknownIdentityField"),&type)==NULL && type==0);
        orig_MGCopyAnswerInternal=incompatibleAnswer;
        nativeCalls=0;
        CFTypeRef answer=my_MGCopyAnswerInternal(CFSTR("SerialNumber"),&type);
#if defined(MKS_ROOTHIDE)
        CHECK([(__bridge id)answer isEqual:MKSMGValue(profile,@"SerialNumber")] && type==9 && nativeCalls==0);
#else
        CHECK([(__bridge id)answer isEqual:@123] && type==6);
#endif
        if(answer)CFRelease(answer);
        nativeCalls=0;
        answer=my_MGCopyAnswerInternal(CFSTR("ChipID"),&type);
#if defined(MKS_ROOTHIDE)
        CHECK(MKSMGValue(profile,@"ChipID")==nil);
        CHECK([(__bridge id)answer isEqual:@123] && type==6 && nativeCalls==1);
#else
        CHECK([(__bridge id)answer isEqual:MKSMGValue(profile,@"ChipID")] && type==6 && nativeCalls==1);
#endif
        if(answer)CFRelease(answer);
        orig_IORegistryEntrySearchCFProperty=missingSearch;
        NSArray *registryKeys=@[@"IOPlatformSerialNumber",@"unique-chip-id",@"die-id",@"IOMACAddress",@"mac-address-wifi0",@"mac-address-bluetooth0",@"local-mac-address",@"udid-version"];
        for(NSString *key in registryKeys) {
            searchCalls=0;
            answer=my_IORegistryEntrySearchCFProperty(0,"IOService",(__bridge CFStringRef)key,NULL,0);
#if defined(MKS_ROOTHIDE)
            CHECK(answer!=NULL && searchCalls==0);
            if([key isEqual:@"IOPlatformSerialNumber"]) CHECK([(__bridge id)answer isEqual:MKSMGValue(profile,@"SerialNumber")]);
            else if(answer) {
                CHECK(CFGetTypeID(answer)==CFDataGetTypeID());
                NSUInteger expected=[key isEqual:@"udid-version"]?4:([key isEqual:@"unique-chip-id"] || [key isEqual:@"die-id"])?8:6;
                CHECK([(__bridge NSData *)answer length]==expected);
                if([key isEqual:@"unique-chip-id"]) {
                    uint64_t actual=0;[(__bridge NSData *)answer getBytes:&actual length:8];
                    CHECK(CFSwapInt64LittleToHost(actual)==[MKSMGValue(profile,@"UniqueChipID") unsignedLongLongValue]);
                }
            }
#else
            CHECK(answer==NULL && searchCalls==1);
#endif
            if(answer)CFRelease(answer);
        }
        searchCalls=0;
        CHECK(my_IORegistryEntrySearchCFProperty(0,"IOService",CFSTR("UnrelatedProperty"),NULL,0)==NULL && searchCalls==1);
        CHECK(my_IORegistryEntrySearchCFProperty(0,"IOService",NULL,NULL,0)==NULL);
        orig_MGCopyAnswerInternal=missingAnswer;
        CHECK(MKSWriteProfile(@{@"schemaVersion":@2,@"enabled":@NO,@"name":@"off",@"values":@{}},path,NULL));
        type=99;
        CHECK(my_MGCopyAnswerInternal(CFSTR("SerialNumber"),&type)==NULL && type==0);
        searchCalls=0;
        CHECK(my_IORegistryEntrySearchCFProperty(0,"IOService",CFSTR("IOPlatformSerialNumber"),NULL,0)==NULL && searchCalls==1);
        [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
#if defined(MKS_ROOTHIDE)
        const char *scheme="roothide";
#else
        const char *scheme="rootless";
#endif
        printf("IDENTITY_ANSWER %s checks=%d failures=%d; native-call ordering, MG types, registry search whitelist and disable verified\n",scheme,checks,failures);
        return failures?1:0;
    }
}
