/*
 * Avalon memory-mapped peripheral that generates VGA
 *
 * Stephen A. Edwards
 * Columbia University
 *
 * Register map:
 * increased to send x and y together
 * Byte Offset  31 ...................... 16 15 ....................... 0
 *        0    |   Ball Y coordinate (0-479)  |  Ball X coordinate (0-639) |
 *
 * Software writes the next ball center into this register. The peripheral
 * latches new coordinates at the start of vertical blanking so the ball doesn't tear while a frame is being drawn.
 */

module vga_ball(input logic        clk,
	        input logic 	   reset,
		input logic [31:0] writedata,
		input logic 	   write,
		input 		   chipselect,
		input logic [2:0]  address,

		output logic [7:0] VGA_R, VGA_G, VGA_B,
		output logic 	   VGA_CLK, VGA_HS, VGA_VS,
		                   VGA_BLANK_n,
		output logic 	   VGA_SYNC_n);

   logic [10:0]	   hcount;
   logic [9:0]     vcount;

   // vars for pending, the ball
   logic [9:0]     pending_x, pending_y;
   
   logic [9:0]     ball_x, ball_y;
   logic [9:0]     pixel_x;
   logic [9:0]     dx_abs, dy_abs;
   logic [19:0]    dx_sq, dy_sq;
   logic           ball_pixel;

   localparam logic [9:0] SCREEN_WIDTH  = 10'd640;
   localparam logic [9:0] SCREEN_HEIGHT = 10'd480;
   localparam logic [9:0] BALL_RADIUS   = 10'd8;
   localparam logic [20:0] BALL_RADIUS_SQ = 21'd64;
	
   vga_counters counters(.clk50(clk), .*);

   always_ff @(posedge clk)
     if (reset) begin
	pending_x <= SCREEN_WIDTH / 2;
	pending_y <= SCREEN_HEIGHT / 2;
	ball_x <= SCREEN_WIDTH / 2;
	ball_y <= SCREEN_HEIGHT / 2;
     end else begin
       if (chipselect && write && address == 3'h0) begin
	  pending_x <= (writedata[15:0] > 16'd639) ? 10'd639 : writedata[9:0];
	  pending_y <= (writedata[31:16] > 16'd479) ? 10'd479 : writedata[25:16];
       end

       if (hcount == 11'd0 && vcount == SCREEN_HEIGHT) begin
	  ball_x <= pending_x;
	  ball_y <= pending_y;
       end
     end

   always_comb begin
      pixel_x = hcount[10:1];
      dx_abs = (pixel_x >= ball_x) ? (pixel_x - ball_x) : (ball_x - pixel_x);
      dy_abs = (vcount >= ball_y) ? (vcount - ball_y) : (ball_y - vcount);
      dx_sq = dx_abs * dx_abs;
      dy_sq = dy_abs * dy_abs;

      ball_pixel = VGA_BLANK_n &&
		   dx_abs <= BALL_RADIUS &&
		   dy_abs <= BALL_RADIUS &&
		   ({1'b0, dx_sq} + {1'b0, dy_sq} <= BALL_RADIUS_SQ);

      {VGA_R, VGA_G, VGA_B} = 24'h000020;
      if (!VGA_BLANK_n)
	{VGA_R, VGA_G, VGA_B} = 24'h000000;
      else if (ball_pixel)
	{VGA_R, VGA_G, VGA_B} = 24'hffffff;
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

