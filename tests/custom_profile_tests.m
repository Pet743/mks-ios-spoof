#import <Foundation/Foundation.h>
#import "MKSProfile.h"
#include <sys/stat.h>
static int checks,failures;
#define CHECK(c) do { checks++;if(!(c)) { failures++;fprintf(stderr,"FAIL line=%d %s\n",__LINE__,#c); } } while(0)
int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc!=3)return 2;
        NSString *directory=@(argv[1]),*output=@(argv[2]);
        [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
        NSMutableArray *cases=[NSMutableArray new];
#ifdef MKS_CUSTOM_PROFILE_API
        NSString *path=[directory stringByAppendingPathComponent:@"generation-options.json"];
        CHECK(MKSGenerateProfileUsingSettings(path,NULL)!=nil);
        CHECK(![NSFileManager.defaultManager fileExistsAtPath:path]);
        CHECK(MKSGenerateProfileForIOSMajor(15,NULL)==nil);
        CHECK(MKSGenerateProfileForIOSMajor(19,NULL)==nil);
        CHECK(!MKSSaveIOSMajor(19,path,NULL));
        for(NSNumber *major in @[@16,@17,@18]) {
            CHECK(MKSSaveIOSMajor(major.integerValue,path,NULL));
            NSData *saved=[NSData dataWithContentsOfFile:path];
            NSDictionary *settings=[NSJSONSerialization JSONObjectWithData:saved options:0 error:NULL];
            CHECK(settings.count==2 && [settings[@"iosMajor"] isEqual:major]);
            CHECK(settings[@"values"]==nil && settings[@"ProductVersion"]==nil);
            struct stat st;CHECK(stat(path.fileSystemRepresentation,&st)==0 && (st.st_mode&0777)==0644);
            NSMutableSet *versions=[NSMutableSet new],*serials=[NSMutableSet new],*udids=[NSMutableSet new];
            NSString *product=major.integerValue==16?@"iPhone15,2":@"iPhone16,2";
            for(int i=0;i<100;i++) {
                NSDictionary *p=MKSGenerateProfileUsingSettings(path,NULL);
                CHECK(p!=nil);CHECK(MKSProfileHTMLRuleErrors(p).count==0);
                NSDictionary *v=p[@"values"];NSString *version=v[@"ProductVersion"];
                CHECK([version hasPrefix:[major.stringValue stringByAppendingString:@"."]]);
                CHECK([v[@"ProductType"] isEqual:product]);
                CHECK([v[@"BuildVersion"] isEqual:MKSBuildForVersion(product,version)]);
                CHECK([v[@"MLBSerialNumber"] isEqual:v[@"SerialNumber"]]);
                CHECK([v[@"DieId"] isEqual:v[@"UniqueChipID"]]);
                CHECK([v[@"EthernetMacAddress"] isEqual:v[@"WifiAddress"]]);
                CHECK([v[@"InternationalMobileEquipmentIdentity2"] isEqual:[v[@"InternationalMobileEquipmentIdentity"] substringToIndex:14]]);
                NSString *line=MKSProfileHTMLParameters(p);NSDictionary *legacy=MKSParseLegacy(line,NULL);
                CHECK(legacy!=nil && MKSProfileHTMLRuleErrors(legacy).count==0);
                CHECK([MKSProfileHTMLParameters(legacy) isEqual:line]);
                CHECK(MKSParseProfile(MKSEncodeProfile(p,NULL),NULL)!=nil);
                [versions addObject:version];[serials addObject:v[@"SerialNumber"]];[udids addObject:v[@"UniqueDeviceID"]];
                [cases addObject:@{@"line":line,@"product":product,@"region":@"US",@"expected":@YES}];
            }
            CHECK(versions.count>1);CHECK(serials.count==100);CHECK(udids.count==100);
            CHECK([saved isEqual:[NSData dataWithContentsOfFile:path]]);
            CHECK(!MKSSaveIOSMajor(0,path,NULL));CHECK([saved isEqual:[NSData dataWithContentsOfFile:path]]);
        }
        for(NSString *bad in @[@"",@"broken",@"{\"schemaVersion\":true,\"iosMajor\":17}",@"{\"schemaVersion\":1,\"iosMajor\":true}",
            @"{\"schemaVersion\":1,\"iosMajor\":19}",@"{\"schemaVersion\":1,\"iosMajor\":17.5}",@"{\"schemaVersion\":1,\"iosMajor\":\"17\"}",
            @"{\"schemaVersion\":1,\"iosMajor\":17,\"extra\":1}",@"{\"schemaVersion\":1,\"values\":{}}"]){
            CHECK([bad writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
            CHECK(MKSGenerateProfileUsingSettings(path,NULL)==nil);
        }
        CHECK([NSFileManager.defaultManager removeItemAtPath:path error:NULL]);
        CHECK(MKSGenerateProfileUsingSettings(path,NULL)!=nil);
        NSMutableArray *fields=[[MKSProfileHTMLParameters(MKSGenerateProfileForIOSMajor(17,NULL)) componentsSeparatedByString:@"----"] mutableCopy];
        for(NSString *chip in @[@"T9999",@"BAD"]) {
            NSMutableArray *bad=[fields mutableCopy];bad[11]=chip;
            NSDictionary *legacy=MKSParseLegacy([bad componentsJoinedByString:@"----"],NULL);
            CHECK(!legacy || MKSProfileHTMLRuleErrors(legacy).count>0);
            [cases addObject:@{@"line":[bad componentsJoinedByString:@"----"],@"product":@"iPhone16,2",@"region":@"US",@"expected":@NO}];
        }
        CHECK([MKSBuildForVersion(@"iPhone16,2",@"18.0") isEqual:@"22A3354"]);
        NSMutableArray *bad=[fields mutableCopy];bad[12]=@"22A3354";bad[13]=@"18.0";
        CHECK(MKSProfileHTMLRuleErrors(MKSParseLegacy([bad componentsJoinedByString:@"----"],NULL)).count>0);
        [cases addObject:@{@"line":[bad componentsJoinedByString:@"----"],@"product":@"iPhone16,2",@"region":@"US",@"expected":@NO}];
        [[NSJSONSerialization dataWithJSONObject:cases options:0 error:NULL] writeToFile:output atomically:YES];
#else
        (void)directory;(void)output;
        CHECK(0);
#endif
        printf("CUSTOM_IOS_MAJOR checks=%d failures=%d html_cases=%lu\n",checks,failures,(unsigned long)cases.count);
        return failures?1:0;
    }
}
