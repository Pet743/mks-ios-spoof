#import <Foundation/Foundation.h>
#include <roothide.h>
#include <sys/param.h>
const char *jbroot(const char *path) {
    static _Thread_local char resolved[PATH_MAX];
    snprintf(resolved,sizeof(resolved),"%s%s",getenv("MKS_TEST_JBROOT"),path);
    return resolved;
}
NSString * __attribute__((overloadable)) jbroot(NSString *path) {
    return [@(getenv("MKS_TEST_JBROOT")) stringByAppendingString:path];
}
