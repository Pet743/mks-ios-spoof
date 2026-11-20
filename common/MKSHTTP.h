#import <Foundation/Foundation.h>

#define MKS_HTTP_PORT 33237
#define MKS_HTTP_TOKEN_PATH @"/var/jb/var/lib/mks-http/token"
#define MKS_HTTP_DEVICE_PATH @"/var/jb/var/lib/mks-http/device-id"
FOUNDATION_EXPORT NSString *MKSHTTPToken(void);
FOUNDATION_EXPORT NSString *MKSHTTPDeviceID(void);
FOUNDATION_EXPORT NSString *MKSHTTPBaseURL(void);
FOUNDATION_EXPORT NSString *MKSHTTPDocumentation(NSString *baseURL,NSString *token);
