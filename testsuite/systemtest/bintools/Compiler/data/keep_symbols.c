/* Two globals the program only writes: without -k, -O3 removes both. */
unsigned int kept_a, kept_b;
int main(void) {
    unsigned int s = 0;
    for (unsigned int i = 0; i < 100; i++) s += i * i;
    kept_a = s;
    kept_b = s ^ 0x55;
    return 0;
}
