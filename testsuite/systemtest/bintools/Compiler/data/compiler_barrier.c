/*
 * Empty inline asm blocks used as compiler barriers: in a branch of
 * their own, inside a loop, in the middle of a basic block, and with
 * and without a memory clobber.
 */
#include <stdio.h>

volatile int sel = 1;
int x = 5;
int arr[8];

static int
in_branch(int c) {
    if (c) {
        __asm__ __volatile__("" ::: "memory");
    }
    return x;
}

static int
in_loop(int n) {
    int sum = 0;
    for (int i = 0; i < n; i++) {
        arr[i] = i;
        __asm__ __volatile__("" ::: "memory");
        sum += arr[i];
    }
    return sum;
}

static int
mid_block(void) {
    x = 7;
    __asm__ __volatile__("");
    return x + 1;
}

int
main() {
    int a = in_branch(sel);
    int b = in_loop(sel * 8);
    int c = mid_block();
    iprintf("%d %d %d\n", a, b, c);
    return 0;
}
