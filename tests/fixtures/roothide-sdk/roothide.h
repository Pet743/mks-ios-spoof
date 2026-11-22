// macOS fixture for compiling the RootHide branch. Device SDK is pinned in build.py.
#pragma once
const char *jbroot(const char *path);
#ifdef __OBJC__
#import <Foundation/Foundation.h>
NSString * __attribute__((overloadable)) jbroot(NSString *path);
#endif
