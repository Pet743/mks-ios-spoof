#import <Foundation/Foundation.h>
FOUNDATION_EXPORT void MKSHTTPStartServer(void);
FOUNDATION_EXPORT int MKSHTTPConfigureDeviceID(const char *deviceID);
// Shared production listener; host tests supply a temporary state dir/token/port.
FOUNDATION_EXPORT int MKSHTTPListen(NSString *stateDirectory,NSString *token,uint16_t port,BOOL loopback);
