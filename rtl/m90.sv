//============================================================================
//  Irem M90 for MiSTer FPGA - Main module
//
//  Copyright (C) 2023 Martin Donlon
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

import board_pkg::*;

module m90 (
    input clk_sys,
    input clk_ram,

    input reset_n,
    output reg ce_pix,

    input board_cfg_t board_cfg,
    
    input z80_reset_n,

    output [7:0] R,
    output [7:0] G,
    output [7:0] B,

    output HSync,
    output VSync,
    output HBlank,
    output VBlank,

    output [15:0] AUDIO_L,
    output [15:0] AUDIO_R,

    input [3:0] coin,
    input [3:0] start_buttons,
    
    input [9:0] p1_input,
    input [9:0] p2_input,
    input [9:0] p3_input,
    input [9:0] p4_input,

    input [23:0] dip_sw,

    input pause_rq,
    output cpu_paused,

    input cpu_turbo,

    input [1:0] sample_attn,

    output [24:0] sdr_sprite_addr,
    input [63:0] sdr_sprite_dout,
    output sdr_sprite_req,
    input sdr_sprite_rdy,
    output sdr_sprite_refresh,

    output [24:0] sdr_bg_addr,
    input [31:0] sdr_bg_dout,
    output sdr_bg_req,
    input sdr_bg_rdy,

    output reg [24:0] sdr_cpu_addr,
    input [63:0] sdr_cpu_dout,
    output reg sdr_cpu_req,
    input sdr_cpu_rdy,

    output [24:0] sdr_audio_addr,
    input [63:0] sdr_audio_dout,
    output sdr_audio_req,
    input sdr_audio_rdy,

    input clk_bram,
    input bram_wr,
    input [7:0] bram_data,
    input [19:0] bram_addr,
    input [4:0] bram_cs,

    input ioctl_download,
    input [15:0] ioctl_index,
	input ioctl_wr,
	input [26:0] ioctl_addr,
	input [7:0] ioctl_dout,
	
    input ioctl_upload,
    output [7:0] ioctl_upload_index,
	output [7:0] ioctl_din,
	input ioctl_rd,
    output ioctl_upload_req,

    input [19:0]     hs_address,
    input [7:0]      hs_din,
    output [7:0]      hs_dout,
    input hs_write,
    input hs_read,

    input [2:0] dbg_en_layers,
    input dbg_solid_sprites,
    input en_sprites,
    input en_audio_filters,

    input sprite_freeze
);

assign ioctl_upload_index = 8'd1;

wire [15:0] rgb_color = palram_dout;
assign R = { rgb_color[4:0], rgb_color[4:2] };
assign G = { rgb_color[9:5], rgb_color[9:7] };
assign B = { rgb_color[14:10], rgb_color[14:12] };

reg paused = 0;
assign cpu_paused = paused;

always @(posedge clk_sys) begin
    if (pause_rq & ~paused) begin
        if (vsync) begin
            paused <= 1;
        end
    end else if (~pause_rq & paused) begin
        paused <= ~vsync;
    end
end


wire ce_13m;
jtframe_frac_cen #(2) pixel_cen
(
    .clk(clk_sys),
    .cen_in(1),
    .n(10'd1),
    .m(10'd3),
    .cen({ce_pix, ce_13m})
);

wire ce_9m, ce_18m;
jtframe_frac_cen #(2) cpu_cen
(
    .clk(clk_sys),
    .cen_in(1),
    .n(10'd9),
    .m(10'd20),
    .cen({ce_9m, ce_18m})
);
wire clock = clk_sys;


wire dma_busy;

wire [15:0] cpu_mem_out;
wire [19:0] cpu_mem_addr;

wire [15:0] cpu_mem_in;

/* Global signals from schematics */
wire cpu_n_mreq, cpu_n_mstb, cpu_n_intak;
wire cpu_n_ube, cpu_r_w, cpu_n_iostb;

wire IOWR = ~cpu_n_iostb & ~cpu_r_w; // IO Write
wire IORD = ~cpu_n_iostb & cpu_r_w; // IO Read
wire MWR = ~cpu_n_mreq & ~cpu_n_mstb & ~cpu_r_w; // Mem Write
wire MRD = ~cpu_n_mreq & cpu_r_w; // Mem Read

wire INTACK = ~cpu_n_intak;

wire [19:0] cpu_word_addr = { cpu_mem_addr[19:1], 1'b0 };
wire [15:0] cpu_rom_data;
wire [15:0] cpu_ram_dout;
wire [19:0] cpu_rom_addr;

wire cpu_rom_memrq;
wire cpu_ram_memrq;
wire ga25_memrq;
wire palram_memrq;

wire [7:0] snd_latch_dout;
wire snd_latch_rdy;

reg [15:0] deferred_ce;
wire ga25_busy;
wire cpu_rom_ready;


always @(posedge clk_sys) begin
    if (!reset_n) begin
        deferred_ce <= 16'd0;
    end else begin
        if (ce_18m) begin
            if (~cpu_rom_ready) begin
                deferred_ce <= deferred_ce + 16'd1;
            end else if (|deferred_ce) begin 
                deferred_ce <= deferred_ce - 16'd1;
            end
        end
    end
end

wire ce_cpu = ~paused & cpu_rom_ready & (ce_18m | cpu_turbo | |deferred_ce);

wire hs_access = hs_read | hs_write;
assign hs_dout = hs_address[0] ? cpu_ram_dout[15:8] : cpu_ram_dout[7:0];

singleport_ram #(.widthad(15), .width(8), .name("CPU0")) cpu_ram_0(
    .clock(clk_sys),
    .address(hs_access ? hs_address[15:1] : cpu_mem_addr[15:1]),
    .q(cpu_ram_dout[7:0]),
    .wren(hs_access ? (hs_write & ~hs_address[0]) : (cpu_ram_memrq & MWR & ~cpu_mem_addr[0])),
    .data(hs_access ? hs_din : cpu_mem_out[7:0])
);

singleport_ram #(.widthad(15), .width(8), .name("CPU1")) cpu_ram_1(
    .clock(clk_sys),
    .address(hs_access ? hs_address[15:1] : cpu_mem_addr[15:1]),
    .q(cpu_ram_dout[15:8]),
    .wren(hs_access ? (hs_write & hs_address[0]) : (cpu_ram_memrq & MWR & ~cpu_n_ube)),
    .data(hs_access ? hs_din : cpu_mem_out[15:8])
);

rom_cache rom_cache(
    .clk(clk_sys),
    .ce(1),
    .reset(~reset_n),

    .clk_ram(clk_ram),
    
    .sdr_addr(sdr_cpu_addr),
    .sdr_data(sdr_cpu_dout),
    .sdr_req(sdr_cpu_req),
    .sdr_rdy(sdr_cpu_rdy),

    .read(MRD & cpu_rom_memrq),
    .rom_word_addr(cpu_rom_addr[19:1]),
    .rom_data(cpu_rom_data),
    .rom_ready(cpu_rom_ready)
);

wire rom0_ce, rom1_ce, ram_cs2;

reg [3:0] bank_select = 4'd0;


// TODO - needs to be adjusted
wire [7:0] switches_p1 = { p1_input[4], p1_input[5], p1_input[6], p1_input[7],      p1_input[3], p1_input[2], p1_input[1], p1_input[0] };
wire [7:0] switches_p2 = { p2_input[4], p2_input[5], p2_input[6], p2_input[7],      p2_input[3], p2_input[2], p2_input[1], p2_input[0] };
wire [7:0] switches_p3 = { p3_input[4], p3_input[5], coin[2],     start_buttons[2], p3_input[3], p3_input[2], p3_input[1], p3_input[0] };
wire [7:0] switches_p4 = { p4_input[4], p4_input[5], coin[3],     start_buttons[3], p4_input[3], p4_input[2], p4_input[1], p4_input[0] };

wire [15:0] switches_p1_p2 = { ~switches_p2, ~switches_p1 };
wire [15:0] switches_p3_p4 = { ~switches_p4, ~switches_p3 };

wire [15:0] flags = { ~dip_sw[23:16], ~dma_busy, 1'b1, 1'b1 /*TEST*/, 1'b1 /*R*/, ~coin[1:0], ~start_buttons[1:0] };

reg [7:0] sys_flags = 0;
wire COIN0 = sys_flags[0];
wire COIN1 = sys_flags[1];
wire SOFT_NL = ~sys_flags[2];
wire CBLK = sys_flags[3];
wire BRQ = ~sys_flags[4];
wire BANK = sys_flags[5];
wire NL = SOFT_NL ^ ~dip_sw[8];

reg sound_reset = 0;

// TODO BANK, CBLK, NL
always @(posedge clk_sys) begin
    if (~reset_n) begin
        bank_select <= 4'd0;
    end else begin
        if (IOWR && cpu_word_addr == 8'h04) bank_select <= cpu_mem_out[3:0];
    end
end

wire [15:0] ga25_dout, palram_dout;

// mux io and memory reads
always_comb begin
    if (INTACK) begin
        cpu_mem_in = { 8'd0, int_vector };
    end else if (MRD) begin
        if (ga25_memrq) cpu_mem_in = ga25_dout;
        else if (palram_memrq) cpu_mem_in = palram_dout;
        else if (cpu_rom_memrq) cpu_mem_in = cpu_rom_data;
        else cpu_mem_in = cpu_ram_dout;
    end else if (IORD) begin
        case ({cpu_word_addr[7:0]})
        8'h00: cpu_mem_in = switches_p1_p2;
        8'h02: cpu_mem_in = flags;
        8'h04: cpu_mem_in = ~dip_sw[15:0];
        8'h06: cpu_mem_in = switches_p3_p4;
        default: cpu_mem_in = 16'hffff;
        endcase
    end else begin
        cpu_mem_in = 16'hffff;
    end
end

wire int_req;
wire [7:0] int_vector;

V33 v35(
    .clk(clk_sys),
    .ce(ce_cpu),

    // Pins
    .n_reset(reset_n),
    .ready(~ga25_busy),
    .n_poll(1),

    .n_ube(cpu_n_ube),
    .r_w(cpu_r_w),
    .n_iostb(cpu_n_iostb),
    .n_mstb(cpu_n_mstb),
    .n_mreq(cpu_n_mreq),

    .n_intak(cpu_n_intak),
    .intreq(0),
    .nmi(0),

    .n_intp0(1),
    .n_intp1(1),
    .n_intp2(1),

    .addr(cpu_mem_addr),
    .dout(cpu_mem_out),
    .din(cpu_mem_in),

    .turbo(cpu_turbo)
);

address_translator address_translator(
    .A(cpu_mem_addr),
    .board_cfg(board_cfg),
    .cpu_rom_memrq(cpu_rom_memrq),
    .cpu_ram_memrq(cpu_ram_memrq),
    .rom_addr(cpu_rom_addr),

    .ga25_memrq,
    .palram_memrq,

    .bank_select
);

wire vblank, hblank, vsync, hsync, hint;

assign HSync = hsync;
assign HBlank = hblank;
assign VSync = vsync;
assign VBlank = vblank;

wire [10:0] ga25_color;

singleport_ram #(.widthad(11), .width(16), .name("PALRAM")) palram(
    .clock(clk_sys),
    .address(palram_memrq ? cpu_mem_addr[11:1] : ga25_color),
    .q(palram_dout),
    .wren(MWR & palram_memrq),
    .data(cpu_mem_out)
);



GA25 ga25(
    .clk(clk_sys),
    .clk_ram(clk_ram),

    .ce(ce_pix),

    .reset(~reset_n),

    .paused(paused),

    .mem_cs(ga25_memrq),
    .mem_wr(MWR),
    .mem_rd(MRD),
    .io_wr(IOWR),

    .busy(ga25_busy),

    .addr(cpu_mem_addr),
    .cpu_din(cpu_mem_out),
    .cpu_dout(ga25_dout),
    

    .NL(NL),

    .sdr_data(sdr_bg_dout),
    .sdr_addr(sdr_bg_addr),
    .sdr_req(sdr_bg_req),
    .sdr_rdy(sdr_bg_rdy),

    .vblank(vblank),
    .hblank(hblank),
    .vsync(vsync),
    .hsync(hsync),

    .hint(hint),

    .color_out(ga25_color),

    .dbg_en_layers(dbg_en_layers)
);


wire [15:0] sound_sample;
sound sound(
    .clk_sys(clk_sys),
    .reset(sound_reset | ~reset_n),

    .paused(paused),

    .sample_attn(sample_attn),

    .latch_wr(IOWR & cpu_word_addr[7:0] == 8'h00),
    .latch_rd(IORD & cpu_word_addr[7:0] == 8'h08),
    .latch_din(cpu_mem_out[7:0]),
    .latch_dout(snd_latch_dout),
    .latch_rdy(snd_latch_rdy),
    
    .rom_addr(bram_addr),
    .rom_data(bram_data),
    .rom_wr(bram_wr & bram_cs[1]),

    .secure_addr(bram_addr[7:0]),
    .secure_data(bram_data),
    .secure_wr(bram_wr & bram_cs[0]),

    .sample(sound_sample),

    .clk_ram(clk_ram),
    .sdr_addr(sdr_audio_addr),
    .sdr_data(sdr_audio_dout),
    .sdr_req(sdr_audio_req),
    .sdr_rdy(sdr_audio_rdy)
);

assign AUDIO_L = sound_sample;
assign AUDIO_R = sound_sample;

endmodule
