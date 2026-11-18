/*
 * Copies, moves and fills of data in non-default address spaces.
 * Struct assignments, shifts of arrays and zeroing loops become
 * memcpy/memmove/memset intrinsics, which must access the right
 * address space and not the default one.
 */

#include <stdio.h>
#include <stdint.h>

#define AS1 __attribute__((address_space(1)))
#define AS2 __attribute__((address_space(2)))

typedef struct { int16_t c; int32_t s, a, b, x, y; } rec;
typedef struct { int32_t v[16]; } big;

AS1 rec r1[8];
AS2 rec r2[8];
rec r0[8];
AS1 big b1[2];
AS1 int32_t w1[32];
AS2 int32_t z2[24];

int main(void) {
    int i;
    uint32_t sum;

    for (i = 0; i < 8; i++) {
        r1[i].c = (int16_t)i; r1[i].s = 100 + i; r1[i].a = i;
        r1[i].b = -i; r1[i].x = 7; r1[i].y = 9;
    }
    /* struct copy inside address space 1 */
    for (i = 7; i > 0; i--) r1[i] = r1[i - 1];
    iprintf("%ld\n", (long)(r1[5].s * 1000 + r1[5].c));

    /* struct copies between address spaces */
    for (i = 0; i < 8; i++) r2[i] = r1[i];
    for (i = 0; i < 8; i++) r0[i] = r2[7 - i];
    sum = 0;
    for (i = 0; i < 8; i++) sum = sum * 3 + r0[i].s + r2[i].c + r0[i].b;
    iprintf("%lu\n", (unsigned long)sum);

    /* larger struct copy */
    for (i = 0; i < 16; i++) b1[0].v[i] = i * i;
    b1[1] = b1[0];
    sum = 0;
    for (i = 0; i < 16; i++) sum += b1[1].v[i];
    iprintf("%lu\n", (unsigned long)sum);

    /* overlapping shift (memmove shaped) */
    for (i = 0; i < 32; i++) w1[i] = i + 1;
    for (i = 31; i > 0; i--) w1[i] = w1[i - 1];
    sum = 0;
    for (i = 0; i < 32; i++) sum = sum * 5 + w1[i];
    iprintf("%lu\n", (unsigned long)sum);

    /* zero fill (memset shaped) and struct zero init */
    for (i = 0; i < 24; i++) z2[i] = 0x55;
    for (i = 0; i < 24; i++) z2[i] = 0;
    for (i = 0; i < 8; i++) r2[i] = (rec){0};
    sum = 0;
    for (i = 0; i < 24; i++) sum += z2[i];
    for (i = 0; i < 8; i++) sum += r2[i].s + r2[i].y;
    iprintf("%lu\n", (unsigned long)sum);
    return 0;
}
