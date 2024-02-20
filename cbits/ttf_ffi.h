#ifndef TTF_FFI_H_
#define TTF_FFI_H_

#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>

SDL_Surface *TTF_FFI_RenderText_Solid(TTF_Font *fnt, const char *text, int col);
SDL_Surface *TTF_FFI_RenderText_Blended(TTF_Font *fnt, const char *text, int col);
SDL_Surface *TTF_FFI_RenderText_LCD(TTF_Font *fnt, const char *text, int fg, int bg);
SDL_Surface * TTF_FFI_RenderUTF8_Blended(TTF_Font *font, const char *text, int fg);

#endif // TTF_FFI_H_


