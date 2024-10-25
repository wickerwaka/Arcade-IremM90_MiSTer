//============================================================================
//  Irem M90 for MiSTer FPGA - Common definitions
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

package board_pkg;

    typedef struct packed {
        bit [24:0] base_addr;
        bit reorder_64;
        bit [4:0] bram_cs;
    } region_t;

    parameter region_t REGION_CPU_ROM       = '{ base_addr:'h000_0000, reorder_64:0, bram_cs:5'b00000 };
    parameter region_t REGION_CPU_RAM       = '{ base_addr:'h010_0000, reorder_64:0, bram_cs:5'b00000 };
    parameter region_t REGION_SOUND_SAMPLES = '{ base_addr:'h030_0000, reorder_64:0, bram_cs:5'b00000 };
    parameter region_t REGION_GFX           = '{ base_addr:'h040_0000, reorder_64:0, bram_cs:5'b00000 };
    parameter region_t REGION_CRYPT         = '{ base_addr:'h000_0000, reorder_64:0, bram_cs:5'b00001 };
    parameter region_t REGION_SOUND_CPU     = '{ base_addr:'h000_0000, reorder_64:0, bram_cs:5'b00010 };

    parameter region_t LOAD_REGIONS[5] = '{
        REGION_CPU_ROM,
        REGION_GFX,
        REGION_SOUND_CPU,
        REGION_SOUND_SAMPLES,
        REGION_CRYPT
    };

    typedef struct packed {
        bit secure;
        bit unused1;
        bit unused2;
        bit rom_2mbit;
        bit [3:0] bank_mask;
    } board_cfg_t;
endpackage