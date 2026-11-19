/* The largest file of the determinism test: several loop nests. */
static int t[64];
static int f(int n, int k) {
    int s = 0;
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++) s += (i * k + j) ^ t[(i + j) & 63];
    return s;
}
static int g(int n) {
    int s = 1;
    for (int i = 0; i < n; i++) { t[i & 63] = s; s = s * 3 + (s >> 2) + i; }
    return s;
}
static int h(int n) {
    int a = 0, b = 1;
    for (int i = 0; i < n; i++) { int c = a + b; a = b; b = c % 100003; }
    return b;
}
int big(int n) { return f(n, 3) + g(n) + h(n) + f(n, 7) - g(n + 1); }
