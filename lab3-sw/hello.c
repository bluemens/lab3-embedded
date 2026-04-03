/*
 * Userspace program that bounces a ball on the VGA display
 * by communicating coordinates and colors to the vga_ball
 * device driver through ioctls
 *
 * Stephen A. Edwards
 * Columbia University
 */

#include <stdio.h>
#include <stdlib.h>
#include "vga_ball.h"
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

#define SCREEN_WIDTH  640
#define SCREEN_HEIGHT 480
#define BALL_RADIUS   16

int vga_ball_fd;

void set_ball(int x, int y, unsigned short ball_color,
	      unsigned short bg_color)
{
	vga_ball_arg_t vla;
	vla.x = x;
	vla.y = y;
	vla.ball_color = ball_color;
	vla.bg_color = bg_color;
	if (ioctl(vga_ball_fd, VGA_BALL_WRITE_BALL, &vla)) {
		perror("ioctl(VGA_BALL_WRITE_BALL) failed");
		return;
	}
}

void read_ball(void)
{
	vga_ball_arg_t vla;
	if (ioctl(vga_ball_fd, VGA_BALL_READ_BALL, &vla)) {
		perror("ioctl(VGA_BALL_READ_BALL) failed");
		return;
	}
	printf("Ball: (%d, %d) color=0x%04x bg=0x%04x\n",
	       vla.x, vla.y, vla.ball_color, vla.bg_color);
}

int main()
{
	static const char filename[] = "/dev/vga_ball";

	int x = SCREEN_WIDTH / 2;
	int y = SCREEN_HEIGHT / 2;
	int dx = 3;
	int dy = 2;

	unsigned short ball_color = RGB565(0xFF, 0xFF, 0x00); /* yellow ball */
	unsigned short bg_color   = RGB565(0x00, 0x00, 0x80); /* dark blue bg */

	printf("VGA ball bouncing demo started\n");

	if ((vga_ball_fd = open(filename, O_RDWR)) == -1) {
		fprintf(stderr, "could not open %s\n", filename);
		return -1;
	}

	printf("initial state: ");
	read_ball();

	while (1) {
		x += dx;
		y += dy;

		/* Bounce off left/right walls */
		if (x <= BALL_RADIUS || x >= SCREEN_WIDTH - 1 - BALL_RADIUS) {
			dx = -dx;
			x += 2 * dx;
		}

		/* Bounce off top/bottom walls */
		if (y <= BALL_RADIUS || y >= SCREEN_HEIGHT - 1 - BALL_RADIUS) {
			dy = -dy;
			y += 2 * dy;
		}

		set_ball(x, y, ball_color, bg_color);
		usleep(16667); /* ~60 frames per second */
	}

	printf("VGA ball bouncing demo terminating\n");
	return 0;
}
