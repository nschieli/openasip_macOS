volatile int a = 3, b = 5;

int
main(void) {
    a = (a + b) << 2;
    return 0;
}
