#import <Foundation/Foundation.h>

#define MKS_HTTP_PORT 33237
#include "MKSPaths.h"
#define MKS_HTTP_TOKEN_PATH MKS_JB_NS_PATH("/var/lib/mks-http/token")
#define MKS_HTTP_DEVICE_PATH MKS_JB_NS_PATH("/var/lib/mks-http/device-id")
FOUNDATION_EXPORT NSString *MKSHTTPToken(void);
FOUNDATION_EXPORT NSString *MKSHTTPDeviceID(void);
FOUNDATION_EXPORT NSString *MKSHTTPBaseURL(void);
FOUNDATION_EXPORT NSString *MKSHTTPDocumentation(NSString *baseURL,NSString *token);
