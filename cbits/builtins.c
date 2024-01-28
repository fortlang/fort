#include <stdio.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <assert.h>
#include <time.h>
#include "builtins.h"

struct termios orig_term = {};
int orig_term_set = 0;

int test_extern_int = 42;

int FORT_argc;
char **FORT_argv;

void FORT_print_Bool(int x)
{
  printf("%s", x ? "True" : "False");
}

void FORT_print_F16(float16_t x)
{
  printf("%f", (float64_t)x);
}

void FORT_print_F32(float32_t x)
{
  printf("%0.9f", x);
}

double clock_gettime_monotonic()
{
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec + t.tv_nsec*1e-9;
}

void FORT_print_F64(float64_t x)
{
  printf("%0.9f", x);
}

void FORT_print_String(char *x)
{
  printf("%s", x);
}

void FORT_print_Pointer(char *x)
{
  printf("%p", (void*)x);
}

void FORT_print_C8(uint8_t x)
{
  printf("%c", x);
}

void FORT_print_U64(uint64_t x)
{
  printf("%llu", x);
}

void FORT_print_ENUM(uint32_t x)
{
  printf("%u", x);
}

void FORT_print_U32(uint32_t x)
{
  printf("%u", x);
}

void FORT_print_U16(uint16_t x)
{
  printf("%u", x);
}

void FORT_print_U8(uint8_t x)
{
  printf("%u", x);
}

void FORT_print_I8(int8_t x)
{
  printf("%d", x);
}

void FORT_print_I16(int16_t x)
{
  printf("%d", x);
}

void FORT_print_I32(int32_t x)
{
  printf("%d", x);
}

void FORT_print_I64(int64_t x)
{
  printf("%lld", x);
}

void termios_setRawMode()
  {
// https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html

  tcgetattr(fileno(stdin), &orig_term);
  orig_term_set = 1;
  struct termios raw = orig_term;


  raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
  raw.c_oflag &= ~(OPOST);
  raw.c_cflag |= (CS8);
  raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);

  raw.c_cc[VMIN] = 1; // set to zero for non-blocking
  raw.c_cc[VTIME] = 0;

  tcsetattr(fileno(stdin), TCSANOW, &raw);

// printf("\x1B[?1049h"); // go into alt buffer
//printf("\x1B[2J"); // clear the screen

    /* int c = 0; */

    /* while(c != 'q') { */
    /*                   c = getchar(); */

    /* } */


  }

void termios_unsetRawMode()
  {
    /* int c = 0; */
    /* while(c != 'q') { */
    /*                   c = getchar(); */

    /* } */
// printf("\x1B[?1049l"); // return from alt buffer
 if (orig_term_set) {
    tcsetattr(fileno(stdin), TCSANOW, &orig_term);
    }
  }

int getTerminalSize() {
  struct winsize ws;
  int size;
  if (ioctl(fileno(stdout), TIOCGWINSZ, &ws) == -1 || ws.ws_col == 0) {
    return 0;
  } else {
    size = (ws.ws_col << 16) | (ws.ws_row & 0xffff);
    return size;
  }
}

long getFileSize(char *filename) {
// struct timespec st_mtimespec;  /* time of last data modification */
    struct stat file_status;
    if (stat(filename, &file_status) < 0) {
        return -1;
    }

    return file_status.st_size;
}
