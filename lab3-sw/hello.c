/*
 * Userspace program that bounces a ball on the VGA display
 * by communicating coordinates to the vga_ball device driver
 * through ioctls
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

void set_ball_position(int x, int y)
{
	vga_ball_arg_t vla;
	vla.position.x = x;
	vla.position.y = y;
	if (ioctl(vga_ball_fd, VGA_BALL_WRITE_POS, &vla)) {
		perror("ioctl(VGA_BALL_WRITE_POS) failed");
		return;
	}
}

void read_ball_position(void)
{
	vga_ball_arg_t vla;
	if (ioctl(vga_ball_fd, VGA_BALL_READ_POS, &vla)) {
		perror("ioctl(VGA_BALL_READ_POS) failed");
		return;
	}
	printf("Ball position: (%d, %d)\n", vla.position.x, vla.position.y);
}

int main()
{
	static const char filename[] = "/dev/vga_ball";

	int x = SCREEN_WIDTH / 2;
	int y = SCREEN_HEIGHT / 2;
	int dx = 3;
	int dy = 2;

	printf("VGA ball bouncing demo started\n");

	if ((vga_ball_fd = open(filename, O_RDWR)) == -1) {
		fprintf(stderr, "could not open %s\n", filename);
		return -1;
	}

	printf("initial state: ");
	read_ball_position();

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

		set_ball_position(x, y);
		usleep(16667); /* ~60 frames per second */
	}

	printf("VGA ball bouncing demo terminating\n");
	return 0;
}
