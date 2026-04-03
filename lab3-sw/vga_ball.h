#ifndef _VGA_BALL_H
#define _VGA_BALL_H

#include <linux/ioctl.h>

typedef struct {
  unsigned short x, y;
  unsigned short ball_color;
  unsigned short bg_color;
} vga_ball_arg_t;

#define VGA_BALL_MAGIC 'q'

/* ioctls and their arguments */
#define VGA_BALL_WRITE_BALL _IOW(VGA_BALL_MAGIC, 1, vga_ball_arg_t)
#define VGA_BALL_READ_BALL  _IOR(VGA_BALL_MAGIC, 2, vga_ball_arg_t)

/* Helper macro: pack 8-bit r, g, b into RGB565 */
#define RGB565(r, g, b) \
  ((unsigned short)(((r) & 0xF8) << 8 | ((g) & 0xFC) << 3 | ((b) >> 3)))

#endif
