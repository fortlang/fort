#include "sdl_ffi.h"

SDL_Event event;

SDL_Event *SDL_FFI_PollEvent()
{
  int i = SDL_PollEvent(&event);
  if (i == 0) { return NULL; }
  return &event;
}

SDL_Event *SDL_FFI_WaitEvent()
{
  SDL_WaitEvent(&event);
  return &event;
}

int SDL_FFI_RenderFillRect(SDL_Renderer *rndr, int x, int y, int w, int h)
{
  SDL_Rect rect;
  rect.x = x;
  rect.y = y;
  rect.w = w;
  rect.h = h;
  return SDL_RenderFillRect(rndr, &rect);
}
int SDL_FFI_FillRect(SDL_Surface *srfc, int x, int y, int w, int h, uint32_t col)
{
  SDL_Rect rect;
  rect.x = x;
  rect.y = y;
  rect.w = w;
  rect.h = h;
  return SDL_FillRect(srfc, &rect, col);
}
uint32_t SDL_FFI_GetEventType(SDL_Event *event) {
  return event->type;
}

char *SDL_FFI_GetTextInputText(SDL_Event *event)
{
  return event->text.text;
}

int SDL_FFI_GetKeyKeysymSym(SDL_Event *event)
{
  return event->key.keysym.sym;
}

int SDL_FFI_RenderCopyRotate(SDL_Renderer *renderer, SDL_Texture *txtr, int x0, int y0, int w0, int h0, int x1, int y1, int w1, int h1, double rot, int cx, int cy)
{
  SDL_Rect r0;
  SDL_Rect r1;
  r0.x = x0;
  r0.y = y0;
  r0.w = w0;
  r0.h = h0;
  r1.x = x1;
  r1.y = y1;
  r1.w = w1;
  r1.h = h1;
  SDL_Point c;
  c.x = cx;
  c.y = cy;
  return SDL_RenderCopyEx(renderer, txtr, &r0, &r1, rot, &c, SDL_FLIP_NONE);
}

int SDL_FFI_RenderCopy(SDL_Renderer *rndr, SDL_Texture *txtr, int x0, int y0, int w0, int h0, int x1, int y1, int w1, int h1)
{
  SDL_Rect r0;
  SDL_Rect r1;
  r0.x = x0;
  r0.y = y0;
  r0.w = w0;
  r0.h = h0;
  r1.x = x1;
  r1.y = y1;
  r1.w = w1;
  r1.h = h1;
  return SDL_RenderCopy(rndr, txtr, &r0, &r1);
}

int SDL_FFI_GetSurfaceWidth(SDL_Surface *srfc)
{
  return srfc->w;
}
int SDL_FFI_GetSurfaceHeight(SDL_Surface *srfc)
{
  return srfc->h;
}

