#include "tceops.h"
volatile unsigned int in[2] = { 0x87654321u, 0x12345678u };
volatile unsigned int out[30];

int main(void) {
    for (int k = 0; k < 2; k++) {
        unsigned int x = in[k], r;
        volatile unsigned int *o = out + 15 * k;
        _TCE_SHL1_32(x, r);   o[0] = r;
        _TCE_SHL2_32(x, r);   o[1] = r;
        _TCE_SHL4_32(x, r);   o[2] = r;
        _TCE_SHL8_32(x, r);   o[3] = r;
        _TCE_SHL16_32(x, r);  o[4] = r;
        _TCE_SHR1_32(x, r);   o[5] = r;
        _TCE_SHR2_32(x, r);   o[6] = r;
        _TCE_SHR4_32(x, r);   o[7] = r;
        _TCE_SHR8_32(x, r);   o[8] = r;
        _TCE_SHR16_32(x, r);  o[9] = r;
        _TCE_SHRU1_32(x, r);  o[10] = r;
        _TCE_SHRU2_32(x, r);  o[11] = r;
        _TCE_SHRU4_32(x, r);  o[12] = r;
        _TCE_SHRU8_32(x, r);  o[13] = r;
        _TCE_SHRU16_32(x, r); o[14] = r;
    }
    return 0;
}
