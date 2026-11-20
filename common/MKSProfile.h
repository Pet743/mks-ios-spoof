#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *MKSConfigPath(void);
FOUNDATION_EXPORT NSArray<NSString *> *MKSConfigPaths(void);
FOUNDATION_EXPORT NSArray<NSString *> *MKSValueKeys(void);
// A missing, disabled or invalid profile always means passthrough.
FOUNDATION_EXPORT NSDictionary * _Nullable MKSParseProfile(NSData *data, NSError **error);
FOUNDATION_EXPORT NSDictionary * _Nullable MKSParseLegacy(NSString *line, NSError **error);
FOUNDATION_EXPORT NSData * _Nullable MKSEncodeProfile(NSDictionary *profile, NSError **error);
FOUNDATION_EXPORT BOOL MKSWriteProfile(NSDictionary *profile, NSString *path, NSError **error);
FOUNDATION_EXPORT NSDictionary *MKSGenerateProfile(void);
FOUNDATION_EXPORT id _Nullable MKSMGValue(NSDictionary * _Nullable profile, NSString *key);
FOUNDATION_EXPORT id _Nullable MKSRegistryValue(NSDictionary * _Nullable profile, NSString *key, id _Nullable original);
FOUNDATION_EXPORT NSString * _Nullable MKSProfileUUID(NSDictionary * _Nullable profile);
FOUNDATION_EXPORT int MKSStringSysctl(NSString *value, void * _Nullable output, size_t * _Nullable length);

@interface MKSProfileStore : NSObject
- (instancetype)initWithPaths:(NSArray<NSString *> *)paths;
- (NSDictionary * _Nullable)snapshot;
@end
NS_ASSUME_NONNULL_END
