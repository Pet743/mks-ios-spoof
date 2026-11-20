#ifndef MKS_BRANCH_H
#define MKS_BRANCH_H
#include <stddef.h>
#include <stdint.h>
#include <string.h>

// Decode only a B, or MOV {X,W}1,#0 followed by B. Never assume offset +4 is a branch.
static inline uintptr_t MKSBranchTarget(const void *bytes,size_t size,uintptr_t pc) {
    if(size<4) return 0;
    uint32_t word=0;memcpy(&word,bytes,4);
    size_t offset=0;
    if(word==0xd2800001U || word==0x52800001U) {
        if(size<8) return 0;
        memcpy(&word,(const uint8_t *)bytes+4,4);offset=4;
    }
    if((word&0xfc000000U)!=0x14000000U) return 0;
    int32_t immediate=(int32_t)(word&0x03ffffffU);
    if(immediate&0x02000000) immediate|=(int32_t)0xfc000000U;
    int64_t delta=(int64_t)immediate*4;
    uintptr_t at=pc+offset;
    if(delta<0 && at<(uintptr_t)-delta) return 0;
    if(delta>=0 && UINTPTR_MAX-at<(uintptr_t)delta) return 0;
    uintptr_t result=delta<0?at-(uintptr_t)-delta:at+(uintptr_t)delta;
    return result==at?0:result;
}
#endif
