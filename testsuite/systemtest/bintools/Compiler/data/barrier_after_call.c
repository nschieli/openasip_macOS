/*
 * Compiler barriers right after a call, in the same basic block: an
 * empty inline asm and a lowered fence, followed by more code, and a
 * barrier as the last thing after a call. Each needs a basic block of
 * its own straight after the one the call ends.
 */
#include <stdio.h>

volatile int sink;
int buf[4];

__attribute__((noinline)) static void
put(int i, int v) {
    buf[i & 3] = v;
    sink = v;
}

static int
asm_after_call(void) {
    put(0, 1);
    __asm__ __volatile__("" ::: "memory");
    put(1, 2);
    return buf[0] + buf[1];
}

static int
fence_after_call(void) {
    put(2, 4);
    __atomic_signal_fence(__ATOMIC_SEQ_CST);
    put(3, 8);
    return buf[2] + buf[3];
}

__attribute__((noinline)) static int
asm_last_after_call(int v) {
    put(0, v);
    __asm__ __volatile__("" ::: "memory");
    return v;
}

/* the shape that found it: a kernel call per step, then an inlined
   helper that starts with a barrier */
static inline void
next(int i) {
    __asm__ __volatile__("" ::: "memory");
    sink = i;
}

static int
calls_in_loop(int n) {
    int sum = 0;
    for (int i = 0; i < n; i++) {
        put(i, i * 3);
        next(i);
        sum += buf[i & 3];
    }
    return sum;
}

int
main() {
    int a = asm_after_call();
    int b = fence_after_call();
    int c = asm_last_after_call(5);
    int d = calls_in_loop(4);
    iprintf("%d %d %d %d\n", a, b, c, d);
    return 0;
}
