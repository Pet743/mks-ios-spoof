#import <Foundation/Foundation.h>
FOUNDATION_EXPORT void MKSHTTPStartServer(void);
FOUNDATION_EXPORT int MKSHTTPConfigureDeviceID(const char *deviceID);
// Local App uses compare-and-set to confirm the value the user saw before rebinding.
FOUNDATION_EXPORT NSDictionary *MKSConfigureDeviceID(NSString *deviceID,id expectedDeviceID);
FOUNDATION_EXPORT BOOL MKSPrepareInstallation(NSString *directory);
// Shared production listener; host tests supply a temporary state dir/token/port.
FOUNDATION_EXPORT int MKSHTTPListen(NSString *stateDirectory,NSString *token,uint16_t port,BOOL loopback);
