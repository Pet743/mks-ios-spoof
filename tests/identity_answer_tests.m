#define MKS_UNIT_TEST 1
#import "../tweak/mks.m"

static int checks,failures;
#define CHECK(value) do { checks++;if(!(value)) failures++; } while(0)
static CFTypeRef missingAnswer(CFStringRef key,uint32_t *type) {
    (void)key;if(type) *type=0;return NULL;
}
static CFTypeRef incompatibleAnswer(CFStringRef key,uint32_t *type) {
    (void)key;if(type) *type=6;return CFBridgingRetain(@123);
}
int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc!=2)return 2;
        NSString *path=@(argv[1]);
        NSDictionary *profile=MKSGenerateProfile();
        CHECK(MKSWriteProfile(profile,path,NULL));
        store=[[MKSProfileStore alloc] initWithPaths:@[path]];
        orig_MGCopyAnswerInternal=missingAnswer;
        for(NSString *key in @[@"SerialNumber",@"MLBSerialNumber",@"UniqueChipID",@"UniqueDeviceIDData",
                              @"InternationalMobileEquipmentIdentity",@"WifiAddress"]) {
            uint32_t type=0xffffffff;
            CFTypeRef answer=my_MGCopyAnswerInternal((__bridge CFStringRef)key,&type);
#if defined(MKS_ROOTHIDE)
            id expected=MKSMGValue(profile,key);
            CHECK(answer && [(__bridge id)answer isEqual:expected]);
            CHECK(type==([expected isKindOfClass:NSNumber.class]?6:[expected isKindOfClass:NSData.class]?10:9));
            if(answer)CFRelease(answer);
            answer=my_MGCopyAnswerInternal((__bridge CFStringRef)key,NULL);
            CHECK(answer && [(__bridge id)answer isEqual:expected]);
            if(answer)CFRelease(answer);
#else
            CHECK(answer==NULL && type==0);
#endif
        }
        uint32_t type=99;
        CHECK(my_MGCopyAnswerInternal(CFSTR("UnknownIdentityField"),&type)==NULL && type==0);
        orig_MGCopyAnswerInternal=incompatibleAnswer;
        CFTypeRef answer=my_MGCopyAnswerInternal(CFSTR("SerialNumber"),&type);
        CHECK([(__bridge id)answer isEqual:@123] && type==6);
        if(answer)CFRelease(answer);
        orig_MGCopyAnswerInternal=missingAnswer;
        CHECK(MKSWriteProfile(@{@"schemaVersion":@2,@"enabled":@NO,@"name":@"off",@"values":@{}},path,NULL));
        type=99;
        CHECK(my_MGCopyAnswerInternal(CFSTR("SerialNumber"),&type)==NULL && type==0);
        [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
#if defined(MKS_ROOTHIDE)
        const char *scheme="roothide";
#else
        const char *scheme="rootless";
#endif
        printf("IDENTITY_ANSWER %s checks=%d failures=%d; missing answers, MG types, unknown keys, incompatible originals and disable verified\n",scheme,checks,failures);
        return failures?1:0;
    }
}
