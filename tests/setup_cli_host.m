#import "../daemon/MKSHTTPServer.h"
int main(int argc,char **argv) {
    return MKSHTTPConfigureDeviceID(argc==2?argv[1]:NULL);
}
