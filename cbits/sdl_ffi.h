#ifndef SDL_FFI_H_
#define SDL_FFI_H_

#include <SDL2/SDL.h>

SDL_Event *SDL_FFI_WaitEvent();
uint32_t SDL_FFI_GetEventType(SDL_Event *event);
int SDL_FFI_FillRect(SDL_Surface *srfc, int x, int y, int w, int h, uint32_t col);
int SDL_FFI_RenderCopy(SDL_Renderer *renderer, SDL_Texture *txtr, int x0, int y0, int w0, int h0, int x1, int y1, int w1, int h1);

int SDL_FFI_RenderCopyRotate(SDL_Renderer *renderer, SDL_Texture *txtr, int x0, int y0, int w0, int h0, int x1, int y1, int w1, int h1, double rot, int cx, int cy);

SDL_Event *SDL_FFI_PollEvent();

int SDL_FFI_GetSurfaceWidth(SDL_Surface *srfc);
int SDL_FFI_GetSurfaceHeight(SDL_Surface *srfc);
int SDL_FFI_RenderFillRect(SDL_Renderer *rndr, int x, int y, int w, int h);
char *SDL_FFI_GetTextInputText(SDL_Event *event);
int SDL_FFI_GetKeyKeysymSym(SDL_Event *event);
#endif // SDL_FFI_H_

