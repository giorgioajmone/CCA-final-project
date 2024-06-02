int putchar(int c);

// Function to clear the screen
void clear_screen() {
    putchar('\033');
    putchar('[');
    putchar('H');
    putchar('\033');
    putchar('[');
    putchar('J');
    putchar(0);
}


void sleep() {
    volatile register int counter = 200000;
    while (counter > 0) {
        counter--;
    }
}

// Function to print a heart frame
void print_heart(char *art[]) {
    for (int i = 0; art[i] != 0; i++) {
        for (int j = 0; art[i][j] != '\0'; j++) {
            putchar(art[i][j]);
        }
        putchar('\n');
    }
}

// Heart frames
char *heart_1[] = {
    "    **    **    ",
    "  ************  ",
    "****************",
    " ****************",
    "  **************  ",
    "   ************   ",
    "    **********    ",
    "     ********     ",
    "      ******      ",
    "       ****       ",
    "        **        ",
    0
};

char *heart_2[] = {
    "  *****     *****  ",
    "********* *********",
    "*******************",
    " ***************** ",
    "  ***************  ",
    "   *************   ",
    "    ***********    ",
    "     *********     ",
    "      *******      ",
    "       *****       ",
    "        ***        ",
    "         *         ",
    0
};

char *heart_3[] = {
    "          *****     *****          ",
    "       ********** **********       ",
    "     *************************     ",
    "   *****************************   ",
    "  ********************************  ",
    " ********************************** ",
    " ********************************** ",
    "  ********************************  ",
    "   ******************************   ",
    "    ****************************    ",
    "      *************************     ",
    "       ***********************      ",
    "         *******************        ",
    "          *****************         ",
    "            ***************         ",
    "              ************          ",
    "                *********           ",
    "                  *****             ",
    "                    **              ",
    0
};

char *heart_4[] = {
    "          *****     *****          ",
    "       ********** **********       ",
    "     *************************     ",
    "   *****************************   ",
    "  ********************************  ",
    " ********************************** ",
    " ********************************** ",
    " ********************************** ",
    "  ********************************  ",
    "   ******************************   ",
    "    ****************************    ",
    "      *************************     ",
    "       ***********************      ",
    "         *******************        ",
    "          *****************         ",
    "            ***************         ",
    "              ************          ",
    "                *********           ",
    "                  *****             ",
    "                    **              ",
    0
};

int main() {
    while (1) {
        clear_screen();
        print_heart(heart_1);  // Print first heart frame
        sleep();

        clear_screen();
        print_heart(heart_2);  // Print second heart frame
        sleep();


        clear_screen();
        print_heart(heart_3);  // Print third heart frame
        sleep();


        clear_screen();
        print_heart(heart_4);  // Print fourth heart frame
        sleep();


        clear_screen();
        print_heart(heart_3);  // Print third heart frame again for reverse effect
        sleep();


        clear_screen();
        print_heart(heart_2);  // Print second heart frame again for reverse effect
        sleep();

    }

    return 0;
}
