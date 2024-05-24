int getchar();
int putchar(int c);
void waitForSnapshot();


int main() {
  char *s = "Hello, one world!\n";
  char *p;
  for (p = s; p < s + 19; p++) putchar(*p);

  waitForSnapshot();

  char *s1 = "Hello, two worlds, Again!\n";
  char *p1;
  for (p1 = s1; p1 < s1 + 27; p1++) putchar(*p1);

  return 0;
}
