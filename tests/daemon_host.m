#import "../common/MKSProfile.h"
// Host UDP regression never starts the privileged device cleaner endpoint.
void MKSCleanerStartServer(void) {}
void MKSHTTPStartServer(void) {}
int MKSHTTPConfigureDeviceID(const char *deviceID) { (void)deviceID;return 1; }
static NSArray *testPaths(void) { return @[@(getenv("MKS_TEST_CONFIG"))]; }
#define MKSConfigPaths testPaths
#import "../daemon/MKSStatus.m"
