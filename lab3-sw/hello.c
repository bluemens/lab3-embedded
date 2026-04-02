/*
 * Userspace program that communicates with the vga_ball device driver
 * through ioctls
 *
 * Stephen A. Edwards
 * Columbia University
 */

#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include "vga_ball.h"

#define SCREEN_WIDTH 
#define SCREEN_HEIGHT 
#define BALL_RADIUS 10
#define FRAME_DELAY_US 

int vga_ball_fd;

/* ctrl-C flips this so the loop can stop cleanly */
static volatile sig_atomic_t keep_running = 1;

static void handle_sigint(int sig)
{
  (void) sig;
  keep_running = 0;
}

// gets the balls position by sending an ioctl to the driver
static int read_ball_position(vga_ball_position_t *position)
{
  if (ioctl(vga_ball_fd, VGA_BALL_READ_POSITION, position)) {
      perror("ioctl(VGA_BALL_READ_POSITION) failed");

      return -1;

  }

  return 0;
}
// sets the balls postion by sending an ioctl to the driver
static int set_ball_position(const vga_ball_position_t *position)
{
  if (ioctl(vga_ball_fd, VGA_BALL_WRITE_POSITION, position)) {

      perror("ioctl(VGA_BALL_WRITE_POSITION) failed");
      return -1;
  }

  return 0;
}

int main(void)
{
  vga_ball_position_t position;
  /* a few pixels per frame i thinkis to look smooth without going wild */
  int x = SCREEN_WIDTH / 2;
  int y = SCREEN_HEIGHT / 2;
  int dx = 4;
  int dy = 3;
  static const char filename[] = "/dev/vga_ball";

  printf("VGA ball userspace program started\n");

  if ( (vga_ball_fd = open(filename, O_RDWR)) == -1) {
    fprintf(stderr, "could not open %s\n", filename);
    return -1;

  }

  signal(SIGINT, handle_sigint);

  if (!read_ball_position(&position)) {
    printf("initial position: (%u, %u)\n", position.x, position.y);
  }

  while (keep_running) {
    /* send the next center point down to the driver/hardware */
    position.x = x;
    position.y = y;

    if (set_ball_position(&position))
      break;

    usleep(FRAME_DELAY_US);

    /* move first then bounce if it hits an edge */
    x += dx;
    y += dy;

    if (x < BALL_RADIUS) {
      x = BALL_RADIUS;
      dx= -dx;

    } else if (x > SCREEN_WIDTH - 1 - BALL_RADIUS) {
      x = SCREEN_WIDTH - 1 - BALL_RADIUS;

      dx = -dx;

    }

    if (y < BALL_RADIUS) {
      y = BALL_RADIUS;
      dy = -dy;

    } else if (y > SCREEN_HEIGHT - 1 - BALL_RADIUS) {
      y = SCREEN_HEIGHT - 1 - BALL_RADIUS;
      dy = -dy;
    }
  }

  close(vga_ball_fd);
  printf("VGA ball userspace program terminating\n");
  return 0;

}
