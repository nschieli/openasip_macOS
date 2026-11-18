/*
 * Two instances of a function unit with a state of its own, ACC_0 and
 * ACC_1, both implement the operations ACCWR, ACCSUM and ACCRD, which
 * have side effects and affect each other (fu_state_order.opp). The
 * calls are pinned to an instance with _TCEFU_<OP>(). Operations on the
 * same instance must stay in program order, also when operations of the
 * same kind on the other instance come between them.
 */

#include <stdio.h>

volatile unsigned int result[2];

static void
print_hex(unsigned int v) {
    int i;
    for (i = 28; i >= 0; i -= 4) {
        unsigned int d = (v >> i) & 0xf;
        putchar(d < 10 ? '0' + d : 'a' + d - 10);
    }
    putchar('\n');
}

int
main(void) {
    unsigned int a, b, i;
    for (i = 0; i < 8; i++)
        _TCEFU_ACCWR("ACC_0", i, 0x11111111u * (i + 1));
    for (i = 0; i < 4; i++)
        _TCEFU_ACCWR("ACC_1", i, 0x01010101u * (i + 7));
    _TCEFU_ACCSUM("ACC_0", 8u);
    _TCEFU_ACCSUM("ACC_1", 8u);
    _TCEFU_ACCRD("ACC_0", 0u, a);
    _TCEFU_ACCRD("ACC_1", 0u, b);
    result[0] = a;
    result[1] = b;
    /* 77777777 and 88888888 */
    print_hex(result[0]);
    print_hex(result[1]);
    return 0;
}
