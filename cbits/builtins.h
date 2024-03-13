#ifndef BUILTINS_H_
#define BUILTINS_H_

#include <inttypes.h>
#include <immintrin.h>

extern int test_extern_int;

extern int FORT_argc;
extern char **FORT_argv;

typedef float float32_t;
typedef double float64_t;

int getErrno();

// void termios_setRawMode();
// void termios_unsetRawMode();
// int getTerminalSize();

// double clock_gettime_monotonic();

void FORT_print_Bool(int x);
void FORT_print_String(char *x);
void FORT_print_Pointer(char *x);

void FORT_print_C8(uint8_t x);

void FORT_print_F64(float64_t x);
void FORT_print_F32(float32_t x);

void FORT_print_I8(int8_t x);
void FORT_print_I16(int16_t x);
void FORT_print_I32(int32_t x);
void FORT_print_I64(int64_t x);

void FORT_print_U8(uint8_t x);
void FORT_print_U16(uint16_t x);
void FORT_print_U32(uint32_t x);
void FORT_print_U64(uint64_t x);
void FORT_print_ENUM(uint32_t x);

typedef __v32qi v32i8;
void FORT_print_VectorV32C8(v32i8 x);

#endif // BUILTINS_H_
