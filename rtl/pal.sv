//============================================================================
//  Irem M90 for MiSTer FPGA - PAL address decoders
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

module address_translator
(
    input logic [19:0] A,

    input logic [3:0] bank_select,
  
    input board_cfg_t board_cfg,

    output [19:0] rom_addr,
    output cpu_rom_memrq,
    output cpu_ram_memrq,

    output ga25_memrq,
    output palram_memrq
);

wire [3:0] bank_a19_16 = ( bank_select & board_cfg.bank_mask ) | ( A[19:16] & ~board_cfg.bank_mask );

always_comb begin
    cpu_ram_memrq = 0;
    cpu_rom_memrq = 0;
    rom_addr = 0;

    ga25_memrq = 0;
	palram_memrq = 0;

	casex (A[19:0])
	// 0x80000-0x8ffff
	20'b1000_xxxx_xxxx_xxxx_xxxx: begin
		cpu_rom_memrq = 1;
		rom_addr = { bank_a19_16, A[15:0] }; // TODO verify
	end
	// 0xd0000-0xdffff
	20'b1101_xxxx_xxxx_xxxx_xxxx: ga25_memrq = 1;
	// 0xa0000-0xaffff
	20'b1010_xxxx_xxxx_xxxx_xxxx: cpu_ram_memrq = 1;
	// 0xe0000-0xeffff
	20'b1110_xxxx_xxxx_xxxx_xxxx: palram_memrq = 1;
	default: begin
		cpu_rom_memrq = 1;
		rom_addr = { 1'h0, A[18:0] };
	end
	endcase
end
endmodule
