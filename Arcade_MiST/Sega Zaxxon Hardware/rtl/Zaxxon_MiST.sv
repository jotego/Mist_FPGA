
module Zaxxon_MiST(
	output        LED,
	output  [5:0] VGA_R,
	output  [5:0] VGA_G,
	output  [5:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        AUDIO_L,
	output        AUDIO_R,	
	input         SPI_SCK,
	output        SPI_DO,
	input         SPI_DI,
	input         SPI_SS2,
	input         SPI_SS3,
	input         CONF_DATA0,
	input         CLOCK_27,

	output [12:0] SDRAM_A,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nWE,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nCS,
	output  [1:0] SDRAM_BA,
	output        SDRAM_CLK,
	output        SDRAM_CKE
);

`include "rtl/build_id.v" 

localparam CONF_STR = {
	"ZAXXON;ROM;",
	"O2,Rotate Controls,Off,On;",
	"O34,Scanlines,Off,25%,50%,75%;",
	"O5,Blend,Off,On;",
	"O6,Flip,Off,On;",
	"O7,Service,Off,On;",
	"T0,Reset;",
	"V,v1.0.",`BUILD_DATE
};

wire          rotate = status[2];
wire [1:0] scanlines = status[4:3];
wire           blend = status[5];
wire           flip  = status[6];
wire        service  = status[7];

assign LED = ~ioctl_downl;
assign SDRAM_CLK = clk_sd;
assign SDRAM_CKE = 1;
assign AUDIO_R = AUDIO_L;

wire clk_sys, clk_sd;
wire pll_locked;
pll_mist pll(
	.inclk0(CLOCK_27),
	.c0(clk_sd),//36
	.c1(clk_sys),//24
	.locked(pll_locked)
	);

wire [31:0] status;
wire  [1:0] buttons;
wire  [1:0] switches;
wire  [7:0] joystick_0;
wire  [7:0] joystick_1;
wire        scandoublerD;
wire        ypbpr;
wire [15:0] audio_r,audio_l;
wire        hs, vs, cs, hb, vb;
wire        blankn;
wire  [2:0] g, r;
wire  [1:0] b;
wire [14:0] rom_addr;
wire [15:0] rom_do;
wire [13:0] gfx_addr;
wire [15:0] gfx_do;
wire        ioctl_downl;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

// ROM structure
// 00000-06FFF CPU ROM   28k  u27-u28-u29-u29-u29
// 07000-0EFFF Tiledata  32k  u91-u90-u93-u92
// 0FOOO-0F7FF char1      2k  u68
// 0F800-0FFFF char2      2k  u69
// 10000-05FFF bg        24k  u113-u112-u111
// 16000-1BFFF spr       24k  u77-u78-u79
// 1C000-1C0FF          256b  u76
// 1C100-1C1FF          256b  u72

data_io data_io(
	.clk_sys       ( clk_sys      ),
	.SPI_SCK       ( SPI_SCK      ),
	.SPI_SS2       ( SPI_SS2      ),
	.SPI_DI        ( SPI_DI       ),
	.ioctl_download( ioctl_downl  ),
	.ioctl_index   ( ioctl_index  ),
	.ioctl_wr      ( ioctl_wr     ),
	.ioctl_addr    ( ioctl_addr   ),
	.ioctl_dout    ( ioctl_dout   )
);

wire [24:0] gfx_ioctl_addr = ioctl_addr - 16'h7000;

reg port1_req, port2_req;
sdram sdram(
	.*,
	.init_n        ( pll_locked   ),
	.clk           ( clk_sd       ),

	// port1 used for main CPU
	.port1_req     ( port1_req    ),
	.port1_ack     ( ),
	.port1_a       ( ioctl_addr[23:1] ),
	.port1_ds      ( {ioctl_addr[0], ~ioctl_addr[0]} ),
	.port1_we      ( ioctl_downl ),
	.port1_d       ( {ioctl_dout, ioctl_dout} ),
	.port1_q       ( ),

	.cpu1_addr     ( ioctl_downl ? 16'hffff : {2'b00, rom_addr[14:1]}),
	.cpu1_q        ( rom_do ),

	// port2 for gfx
	.port2_req     ( port2_req ),
	.port2_ack     ( ),
	.port2_a       ( {gfx_ioctl_addr[23:15], gfx_ioctl_addr[13:0]} ),
	.port2_ds      ( {gfx_ioctl_addr[14], ~gfx_ioctl_addr[14]} ),
	.port2_we      ( ioctl_downl ),
	.port2_d       ( {ioctl_dout, ioctl_dout} ),
	.port2_q       ( ),

	.gfx_addr      ( gfx_addr ),
	.gfx_q         ( gfx_do )
);

always @(posedge clk_sys) begin
	reg        ioctl_wr_last = 0;

	ioctl_wr_last <= ioctl_wr;
	if (ioctl_downl) begin
		if (~ioctl_wr_last && ioctl_wr) begin
			port1_req <= ~port1_req;
			port2_req <= ~port2_req;
		end
	end
end

reg reset = 1;
reg rom_loaded = 0;
always @(posedge clk_sd) begin
	reg ioctl_downlD;
	ioctl_downlD <= ioctl_downl;

	if (ioctl_downlD & ~ioctl_downl) rom_loaded <= 1;
	reset <= status[0] | buttons[1] | ~rom_loaded;
end

zaxxon zaxxon(
	.clock_24(clk_sys),
	.reset(reset),
	
	.video_r(r),
	.video_g(g),
	.video_b(b),
	.video_blankn(blankn),
	.video_hs(hs),
	.video_vs(vs),
	.video_csync(cs),
	
	.audio_out_r(audio_r),
	.audio_out_l(audio_l),

	.coin1(btn_coin),
	.coin2(btn_coin),
	.start2(btn_two_players),
	.start1(btn_one_player),
	.left(m_left),
	.right(m_right),
	.up(m_up),
	.down(m_down),
	.fire(m_fire),
	.service(service),

	.flip_screen(flip),

	.cpu_rom_addr ( rom_addr        ),
	.cpu_rom_do   ( rom_addr[0] ? rom_do[15:8] : rom_do[7:0] ),
	.map_addr     ( gfx_addr ),
	.map_do       ( gfx_do   ),

	.dl_addr      ( ioctl_addr[16:0] ),
	.dl_data      ( ioctl_dout ),
	.dl_wr        ( ioctl_wr )
);

mist_video #(.COLOR_DEPTH(3), .SD_HCNT_WIDTH(10)) mist_video(
	.clk_sys        ( clk_sys          ),
	.SPI_SCK        ( SPI_SCK          ),
	.SPI_SS3        ( SPI_SS3          ),
	.SPI_DI         ( SPI_DI           ),
	.R              ( blankn ? r : 0   ),
	.G              ( blankn ? g : 0   ),
	.B              ( blankn ? {b,b[1]} : 0 ),
	.HSync          ( hs               ),
	.VSync          ( vs               ),
	.VGA_R          ( VGA_R            ),
	.VGA_G          ( VGA_G            ),
	.VGA_B          ( VGA_B            ),
	.VGA_VS         ( VGA_VS           ),
	.VGA_HS         ( VGA_HS           ),
	.ce_divider     ( 1'b1             ),
	.blend          ( blend            ),
	.rotate         ( {flip, rotate}   ),
	.scandoubler_disable(scandoublerD  ),
	.scanlines      ( scanlines        ),
	.ypbpr          ( ypbpr            )
	);

user_io #(
	.STRLEN(($size(CONF_STR)>>3)))
user_io(
	.clk_sys        (clk_sys        ),
	.conf_str       (CONF_STR       ),
	.SPI_CLK        (SPI_SCK        ),
	.SPI_SS_IO      (CONF_DATA0     ),
	.SPI_MISO       (SPI_DO         ),
	.SPI_MOSI       (SPI_DI         ),
	.buttons        (buttons        ),
	.switches       (switches       ),
	.scandoubler_disable (scandoublerD	  ),
	.ypbpr          (ypbpr          ),
	.key_strobe     (key_strobe     ),
	.key_pressed    (key_pressed    ),
	.key_code       (key_code       ),
	.joystick_0     (joystick_0     ),
	.joystick_1     (joystick_1     ),
	.status         (status         )
	);

dac #(
	.C_bits(16))
dac_l(
	.clk_i(clk_sys),
	.res_n_i(1),
	.dac_i(audio),
	.dac_o(AUDIO_L)
	);

wire m_up     = ~rotate ? (flip ? btn_left  | joystick_0[1] | joystick_1[1] : btn_right | joystick_0[0] | joystick_1[0]) : btn_up    | joystick_0[3] | joystick_1[3];
wire m_down   = ~rotate ? (flip ? btn_right | joystick_0[0] | joystick_1[0] : btn_left  | joystick_0[1] | joystick_1[1]) : btn_down  | joystick_0[2] | joystick_1[2];
wire m_left   = ~rotate ? (flip ? btn_down  | joystick_0[2] | joystick_1[2] : btn_up    | joystick_0[3] | joystick_1[3]) : btn_left  | joystick_0[1] | joystick_1[1];
wire m_right  = ~rotate ? (flip ? btn_up    | joystick_0[3] | joystick_1[3] : btn_down  | joystick_0[2] | joystick_1[2]) : btn_right | joystick_0[0] | joystick_1[0];
wire m_fire   = btn_fire1 | joystick_0[4] | joystick_1[4];

reg btn_one_player = 0;
reg btn_two_players = 0;
reg btn_left = 0;
reg btn_right = 0;
reg btn_down = 0;
reg btn_up = 0;
reg btn_fire1 = 0;
//reg btn_fire2 = 0;
//reg btn_fire3 = 0;
reg btn_coin  = 0;
wire       key_pressed;
wire [7:0] key_code;
wire       key_strobe;

always @(posedge clk_sys) begin
	if(key_strobe) begin
		case(key_code)
			'h75: btn_up          <= key_pressed; // up
			'h72: btn_down        <= key_pressed; // down
			'h6B: btn_left        <= key_pressed; // left
			'h74: btn_right       <= key_pressed; // right
			'h76: btn_coin        <= key_pressed; // ESC
			'h05: btn_one_player  <= key_pressed; // F1
			'h06: btn_two_players <= key_pressed; // F2
//			'h14: btn_fire3       <= key_pressed; // ctrl
//			'h11: btn_fire2       <= key_pressed; // alt
			'h29: btn_fire1       <= key_pressed; // Space
		endcase
	end
end

endmodule 
