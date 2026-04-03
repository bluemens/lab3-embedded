/*
 * Avalon memory-mapped peripheral that generates VGA
 * with a bouncing ball at software-controllable coordinates and colors
 *
 * Stephen A. Edwards
 * Columbia University
 *
 * Register map (16-bit writedata):
 *
 * Word Offset   15 ·········· 0          Meaning
 *      0       |    ball_x    |   X coordinate of ball center (0–639)
 *      1       |    ball_y    |   Y coordinate of ball center (0–479)
 *      2       | R[15:11] G[10:5] B[4:0] |  Ball color (RGB565)
 *      3       | R[15:11] G[10:5] B[4:0] |  Background color (RGB565)
 *
 * Byte addresses from the CPU: 0=ball_x, 2=ball_y, 4=ball_color, 6=bg_color
 * Ball radius is fixed at 16 pixels in hardware.
 * Coordinates are latched at the start of vertical blanking to
 * prevent tearing.
 */

module vga_ball(input logic         clk,
		input logic 	    reset,
		input logic [15:0]  writedata,
		input logic 	    write,
		input 		    chipselect,
		input logic [2:0]   address,

		output logic [7:0]  VGA_R, VGA_G, VGA_B,
		output logic 	    VGA_CLK, VGA_HS, VGA_VS,
		                    VGA_BLANK_n,
		output logic 	    VGA_SYNC_n);

   logic [10:0]    hcount;
   logic [9:0]     vcount;

   /* Ball position registers (written by software) */
   logic [15:0]    ball_x, ball_y;

   /* Color registers (RGB565) */
   logic [15:0]    ball_color, bg_color;

   /* Active copies latched during vertical blanking (used for drawing) */
   logic [15:0]    ball_x_active, ball_y_active;
   logic [15:0]    ball_color_active, bg_color_active;

   parameter BALL_RADIUS = 16;

   vga_counters counters(.clk50(clk), .*);

   /* ---- Register writes from the Avalon bus ---- */
   always_ff @(posedge clk)
     if (reset) begin
	ball_x     <= 16'd320;
	ball_y     <= 16'd240;
	ball_color <= 16'hFFFF;  /* white */
	bg_color   <= 16'h0010;  /* dark blue */
     end else if (chipselect && write)
       case (address)
	 3'h0 : ball_x     <= writedata;
	 3'h1 : ball_y     <= writedata;
	 3'h2 : ball_color <= writedata;
	 3'h3 : bg_color   <= writedata;
       endcase

   /* ---- Latch at start of vertical blanking to prevent tearing ---- */
   always_ff @(posedge clk)
     if (reset) begin
	ball_x_active     <= 16'd320;
	ball_y_active     <= 16'd240;
	ball_color_active <= 16'hFFFF;
	bg_color_active   <= 16'h0010;
     end else if (vcount == 10'd480 && hcount == 11'd0) begin
	ball_x_active     <= ball_x;
	ball_y_active     <= ball_y;
	ball_color_active <= ball_color;
	bg_color_active   <= bg_color;
     end

   /* ---- Expand RGB565 to RGB888 ---- */
   logic [7:0] ball_r, ball_g, ball_b;
   logic [7:0] bg_r, bg_g, bg_b;

   assign ball_r = {ball_color_active[15:11], ball_color_active[15:13]};
   assign ball_g = {ball_color_active[10:5],  ball_color_active[10:9]};
   assign ball_b = {ball_color_active[4:0],   ball_color_active[4:2]};

   assign bg_r = {bg_color_active[15:11], bg_color_active[15:13]};
   assign bg_g = {bg_color_active[10:5],  bg_color_active[10:9]};
   assign bg_b = {bg_color_active[4:0],   bg_color_active[4:2]};

   /* ---- Ball drawing logic ---- */
   logic [9:0] pixel_x;
   logic [9:0] pixel_y;
   assign pixel_x = hcount[10:1];   /* pixel column 0-639 in active area */
   assign pixel_y = vcount[9:0];    /* pixel row    0-479 in active area */

   /* Absolute distance from pixel to ball center */
   logic [9:0] abs_dx, abs_dy;
   assign abs_dx = (pixel_x >= ball_x_active[9:0])
		   ? (pixel_x - ball_x_active[9:0])
		   : (ball_x_active[9:0] - pixel_x);
   assign abs_dy = (pixel_y >= ball_y_active[9:0])
		   ? (pixel_y - ball_y_active[9:0])
		   : (ball_y_active[9:0] - pixel_y);

   /* Circle test: dx^2 + dy^2 <= R^2 */
   logic [19:0] dist_sq;
   assign dist_sq = abs_dx * abs_dx + abs_dy * abs_dy;

   logic in_ball;
   assign in_ball = (dist_sq <= BALL_RADIUS * BALL_RADIUS);

   /* ---- Pixel output ---- */
   always_comb begin
      {VGA_R, VGA_G, VGA_B} = {8'h0, 8'h0, 8'h0};
      if (VGA_BLANK_n)
	if (in_ball)
	  {VGA_R, VGA_G, VGA_B} = {ball_r, ball_g, ball_b};
	else
	  {VGA_R, VGA_G, VGA_B} = {bg_r, bg_g, bg_b};
   end

endmodule

module vga_counters(
 input logic 	     clk50, reset,
 output logic [10:0] hcount,  // hcount[10:1] is pixel column
 output logic [9:0]  vcount,  // vcount[9:0] is pixel row
 output logic 	     VGA_CLK, VGA_HS, VGA_VS, VGA_BLANK_n, VGA_SYNC_n);

/*
 * 640 X 480 VGA timing for a 50 MHz clock: one pixel every other cycle
 *
 * HCOUNT 1599 0             1279       1599 0
 *             _______________              ________
 * ___________|    Video      |____________|  Video
 *
 *
 * |SYNC| BP |<-- HACTIVE -->|FP|SYNC| BP |<-- HACTIVE
 *       _______________________      _____________
 * |____|       VGA_HS          |____|
 */
   // Parameters for hcount
   parameter HACTIVE      = 11'd 1280,
             HFRONT_PORCH = 11'd 32,
             HSYNC        = 11'd 192,
             HBACK_PORCH  = 11'd 96,
             HTOTAL       = HACTIVE + HFRONT_PORCH + HSYNC +
                            HBACK_PORCH; // 1600

   // Parameters for vcount
   parameter VACTIVE      = 10'd 480,
             VFRONT_PORCH = 10'd 10,
             VSYNC        = 10'd 2,
             VBACK_PORCH  = 10'd 33,
             VTOTAL       = VACTIVE + VFRONT_PORCH + VSYNC +
                            VBACK_PORCH; // 525

   logic endOfLine;

   always_ff @(posedge clk50 or posedge reset)
     if (reset)          hcount <= 0;
     else if (endOfLine) hcount <= 0;
     else  	         hcount <= hcount + 11'd 1;

   assign endOfLine = hcount == HTOTAL - 1;

   logic endOfField;

   always_ff @(posedge clk50 or posedge reset)
     if (reset)          vcount <= 0;
     else if (endOfLine)
       if (endOfField)   vcount <= 0;
       else              vcount <= vcount + 10'd 1;

   assign endOfField = vcount == VTOTAL - 1;

   // Horizontal sync: from 0x520 to 0x5DF (0x57F)
   // 101 0010 0000 to 101 1101 1111
   assign VGA_HS = !( (hcount[10:8] == 3'b101) &
		      !(hcount[7:5] == 3'b111));
   assign VGA_VS = !( vcount[9:1] == (VACTIVE + VFRONT_PORCH) / 2);

   assign VGA_SYNC_n = 1'b0; // For putting sync on the green signal; unused

   // Horizontal active: 0 to 1279     Vertical active: 0 to 479
   // 101 0000 0000  1280	       01 1110 0000  480
   // 110 0011 1111  1599	       10 0000 1100  524
   assign VGA_BLANK_n = !( hcount[10] & (hcount[9] | hcount[8]) ) &
			!( vcount[9] | (vcount[8:5] == 4'b1111) );

   /* VGA_CLK is 25 MHz
    *             __    __    __
    * clk50    __|  |__|  |__|
    *
    *             _____       __
    * hcount[0]__|     |_____|
    */
   assign VGA_CLK = hcount[0]; // 25 MHz clock: rising edge sensitive

endmodule
