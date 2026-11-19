/* Multi-file program for tcetest_determinism.sh: files of very different
 * sizes, so parallel compile jobs finish in varying order. */
#include <stdio.h>
int big(int n);
int small1(int x);
int small2(int x);
int small3(int x);
int main(void) {
    printf("%d\n", big(10) + small1(1) + small2(2) + small3(3));
    return 0;
}
