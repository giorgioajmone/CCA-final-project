// Dangerous, we should add volatile
int* PUT_ADDR = (int *)0xF000fff0;
int* GET_ADDR = (int *)0xF000fff4;
int* FINISH_ADDR = (int *)0xF000fff8;
int* WAIT_ADDR = (int *)0xF000fffC;

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
  // Set the value of the x10 to 0. 
  __asm__ volatile(
    "li x10, 0 \n\t"
    :
    :
    : "x10"
  );

  // Write anything to the wait address. 
  *WAIT_ADDR = 'b';

  while (1) {
    // read the x10 value and put it in the result.
    volatile register int result = 0;
    __asm__ volatile(
      "mv %0, x10 \n\t"
      : "=r" (result)
    );

    if (result == 1) {
      break;
    }
  }

}
