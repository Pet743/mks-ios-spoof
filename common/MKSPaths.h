#pragma once

#if defined(MKS_ROOTHIDE)
#include <roothide.h>
#define MKS_JB_PATH(path) jbroot(path)
#define MKS_JB_NS_PATH(path) jbroot(@path)
#else
#define MKS_JB_PATH(path) "/var/jb" path
#define MKS_JB_NS_PATH(path) @"/var/jb" path
#endif
