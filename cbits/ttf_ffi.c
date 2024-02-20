#include "ttf_ffi.h"

SDL_Surface *TTF_FFI_RenderText_Blended(TTF_Font *fnt, const char *text, int col)
{
  SDL_Color c;
  c.r = col >> 24;
  c.g = col >> 16;
  c.b = col >> 8;
  c.a = col;
  return TTF_RenderText_Blended(fnt, text, c);

}

SDL_Surface *TTF_FFI_RenderText_Solid(TTF_Font *fnt, const char *text, int col)
{
  SDL_Color c;
  c.r = col >> 24;
  c.g = col >> 16;
  c.b = col >> 8;
  c.a = col;
  return TTF_RenderText_Solid(fnt, text, c);
}

SDL_Surface *TTF_FFI_RenderText_LCD(TTF_Font *fnt, const char *text, int fg, int bg)
{
  SDL_Color fgc;
  fgc.r = fg >> 24;
  fgc.g = fg >> 16;
  fgc.b = fg >> 8;
  fgc.a = fg;

  SDL_Color bgc;
  bgc.r = bg >> 24;
  bgc.g = bg >> 16;
  bgc.b = bg >> 8;
  bgc.a = bg;

  return TTF_RenderText_LCD(fnt, text, fgc, bgc);
}

SDL_Surface * TTF_FFI_RenderUTF8_Blended(TTF_Font *font, const char *text, int fg)
{
  SDL_Color fgc;
  fgc.r = fg >> 24;
  fgc.g = fg >> 16;
  fgc.b = fg >> 8;
  fgc.a = fg;
  return TTF_RenderUTF8_Blended(font, text, fgc);
}

