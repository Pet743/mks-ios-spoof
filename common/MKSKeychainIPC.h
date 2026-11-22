#import <Foundation/Foundation.h>
#include <sys/types.h>

#include "MKSPaths.h"
#ifdef MKS_HTTP_TEST
#define MKS_KEYCHAIN_SOCKET getenv("MKS_TEST_SOCKET")
#else
#define MKS_KEYCHAIN_SOCKET MKS_JB_PATH("/var/run/mks-keychain.sock")
#endif
#define MKS_LOCAL_STATUS_COMMAND "LOCAL_STATUS_V1\n"
#define MKS_KEYCHAIN_COMMAND "CLEAN_KEYCHAIN_V1\n"
FOUNDATION_EXPORT BOOL MKSKeychainRequestValid(NSData *request);
FOUNDATION_EXPORT BOOL MKSKeychainPeerAllowed(uid_t uid,NSString *processPath,NSString *appPath);
FOUNDATION_EXPORT NSDictionary *MKSRequestKeychainClean(void);
FOUNDATION_EXPORT NSDictionary *MKSLocalSetupRequest(NSData *request);
FOUNDATION_EXPORT NSDictionary *MKSRequestLocalStatus(void);
FOUNDATION_EXPORT NSDictionary *MKSRequestDeviceBinding(NSString *deviceID,id expectedDeviceID);
