#import "../daemon/MKSHTTPServer.h"
#include <unistd.h>
int MKSRespring(void) {
    const char *path=getenv("MKS_TEST_RESPRING");
    FILE *f=fopen(path,"a");if(!f) return -1;fputs("respring\n",f);fclose(f);
    return getenv("MKS_TEST_RESPRING_FAIL")?-1:0;
}
int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc!=3) return 2;
        return MKSHTTPListen(@(argv[1]),@(argv[2]),0,YES)<0?1:0;
    }
}
