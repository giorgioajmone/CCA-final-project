// Dangerous, we should add volatile
int* PUT_ADDR = (int *)0xF000fff0;
int* GET_ADDR = (int *)0xF000fff4;
int* FINISH_ADDR = (int *)0xF000fff8;
int* WAIT_ADDR = (int *)0xF000fffA;
int

int getchar() {
  return *GET_ADDR;
}

int putchar(int c) {
  *PUT_ADDR = c;
  return c;
}

int exit(int c) {
  *FINISH_ADDR = c;
  return c;
}

void waitForSnapshot(){ 
  volatile asm 
}
