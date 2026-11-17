/*
 * Atomic fences: signal fences and thread fences of each ordering.
 */
#include <stdio.h>

volatile int flag = 0;
int x = 3;

static int
signal_fence(volatile int* p) {
    while (*p) {
    }
    __atomic_signal_fence(__ATOMIC_SEQ_CST);
    return x;
}

static int
thread_fences(int v) {
    x = v;
    __atomic_thread_fence(__ATOMIC_RELEASE);
    flag = 0;
    __atomic_thread_fence(__ATOMIC_ACQUIRE);
    int r = x;
    __atomic_thread_fence(__ATOMIC_ACQ_REL);
    __atomic_thread_fence(__ATOMIC_SEQ_CST);
    return r;
}

int
main() {
    int a = signal_fence(&flag);
    int b = thread_fences(9);
    iprintf("%d %d\n", a, b);
    return 0;
}
