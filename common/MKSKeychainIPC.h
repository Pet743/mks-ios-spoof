#import <Foundation/Foundation.h>
#include <sys/types.h>

#define MKS_KEYCHAIN_SOCKET "/var/jb/var/run/mks-keychain.sock"
#define MKS_KEYCHAIN_COMMAND "CLEAN_KEYCHAIN_V1\n"
FOUNDATION_EXPORT BOOL MKSKeychainRequestValid(NSData *request);
FOUNDATION_EXPORT BOOL MKSKeychainPeerAllowed(uid_t uid,NSString *processPath,NSString *appPath);
FOUNDATION_EXPORT NSDictionary *MKSRequestKeychainClean(void);
