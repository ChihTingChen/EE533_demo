`timescale 1ns / 1ps

module TensorUnit (
    input         clk,
    input         reset,

    input         mmio_we,
    input  [3:0]  mmio_waddr,
    input  [31:0] mmio_wdata,
    input  [3:0]  mmio_raddr,
    output reg [31:0] mmio_rdata,

    output reg        dmem_re,
    output reg [8:0]  dmem_raddr,
    input      [63:0] dmem_rdata,

    output reg        dmem_we,
    output reg [8:0]  dmem_waddr,
    output reg [63:0] dmem_wdata,

    output reg [5:0]  rom_addr,
    input      [63:0] rom_rdata,

    output reg        busy,
    output reg        result_tumor
);

    localparam integer CONV_SHIFT       = 7;
    localparam [5:0]   ROM_CONV1_W_BASE = 6'h00;
    localparam [5:0]   ROM_CONV1_B_BASE = 6'h0e;
    localparam [5:0]   ROM_FC_W_BASE    = 6'h10;
    localparam [5:0]   ROM_FC_B_BASE    = 6'h22;

    localparam [4:0]
        S_IDLE          = 5'd0,
        S_CP_LOAD_BIAS  = 5'd1,
        S_CP_BIAS_WAIT  = 5'd2,
        S_CP_BIAS_USE   = 5'd3,
        S_CP_NEW_CONV   = 5'd4,
        S_CP_MAC_ISSUE  = 5'd5,
        S_CP_MAC_WAIT   = 5'd6,
        S_CP_MAC_DO     = 5'd7,
        S_CP_FINALIZE   = 5'd8,
        S_CP_PACK       = 5'd9,
        S_CP_FLUSH      = 5'd10,
        S_CP_DONE       = 5'd11,
        S_FC_LOAD_BIAS  = 5'd12,
        S_FC_BIAS_WAIT  = 5'd13,
        S_FC_BIAS_USE   = 5'd14,
        S_FC_MAC_ISSUE  = 5'd15,
        S_FC_MAC_WAIT   = 5'd16,
        S_FC_MAC_DO     = 5'd17,
        S_FC_DONE       = 5'd18,
        S_CP_MAC_ACC    = 5'd19,
        S_FC_MAC_ACC    = 5'd20,
        S_CP_ADDR_PRE   = 5'd21;

    reg [4:0] state, next_state;

    reg [1:0] reg_cmd;
    reg [8:0] reg_x_base, reg_y_base;

    wire fsm_done = (state == S_CP_DONE || state == S_FC_DONE);

    always @(*) begin
        case (mmio_raddr)
            4'h0:    mmio_rdata = {30'd0, reg_cmd};
            4'h1:    mmio_rdata = {23'd0, reg_x_base};
            4'h2:    mmio_rdata = {23'd0, reg_y_base};
            4'h3:    mmio_rdata = {30'd0, result_tumor, busy};
            default: mmio_rdata = 32'd0;
        endcase
    end

    wire start_pulse = mmio_we && mmio_waddr == 4'h0 && mmio_wdata[1:0] != 2'd0;

    always @(posedge clk) begin
        if (reset) begin
            reg_cmd    <= 2'd0;
            reg_x_base <= 9'd0;
            reg_y_base <= 9'd0;
        end else if (fsm_done) begin
            reg_cmd <= 2'd0;
        end else if (mmio_we) begin
            case (mmio_waddr)
                4'h0: reg_cmd    <= mmio_wdata[1:0];
                4'h1: reg_x_base <= mmio_wdata[8:0];
                4'h2: reg_y_base <= mmio_wdata[8:0];
                default: ;
            endcase
        end
    end

    reg [1:0] oc;
    reg [2:0] py, px;
    reg [1:0] j_idx, i_idx;
    reg [1:0] ic;
    reg [1:0] ky, kx;
    reg signed [31:0] acc;
    reg signed [31:0] best;

    reg [63:0] out_word_buf;
    reg [2:0]  out_byte_pos;
    reg [4:0]  out_word_count;

    reg [7:0]  fc_idx;
    reg signed [31:0] bias_val;

    wire [4:0] cur_oy = {py, 2'd0} + {3'd0, j_idx} + {3'd0, ky};
    wire [4:0] cur_ox = {px, 2'd0} + {3'd0, i_idx} + {3'd0, kx};

    wire [9:0] oy28 = ({5'd0, cur_oy} << 4) + ({5'd0, cur_oy} << 3) + ({5'd0, cur_oy} << 2);
    wire [10:0] pix_idx = oy28 + {6'd0, cur_ox};
    wire [12:0] img_byte_addr = (pix_idx << 1) + pix_idx + {11'd0, ic};
    wire [9:0]  img_word_addr = img_byte_addr[12:3];
    wire [2:0]  img_byte_pos  = img_byte_addr[2:0];

    wire [6:0] oc27   = ({5'd0, oc} << 4) + ({5'd0, oc} << 3) + ({5'd0, oc} << 1) + {5'd0, oc};
    wire [4:0] kc_off = ({3'd0, ic} << 3) + {3'd0, ic} + ({3'd0, ky} << 1) + {3'd0, ky} + {3'd0, kx};
    wire [6:0] cw_byte_addr = oc27 + {2'd0, kc_off};
    wire [3:0] cw_word_addr = cw_byte_addr[6:3];
    wire [2:0] cw_byte_pos  = cw_byte_addr[2:0];

    wire [1:0] next_oc_internal    = oc + 2'd1;
    wire [5:0] next_bias_word_addr = ROM_CONV1_B_BASE + {5'd0, next_oc_internal[1]};

    wire [4:0] fcw_word_addr = fc_idx[7:3];
    wire [2:0] fcw_byte_pos  = fc_idx[2:0];

    function signed [31:0] s8_to_s32(input [7:0] b);
        s8_to_s32 = {{24{b[7]}}, b};
    endfunction

    function [7:0] byte_at(input [63:0] w, input [2:0] pos);
        case (pos)
            3'd0: byte_at = w[ 7: 0];
            3'd1: byte_at = w[15: 8];
            3'd2: byte_at = w[23:16];
            3'd3: byte_at = w[31:24];
            3'd4: byte_at = w[39:32];
            3'd5: byte_at = w[47:40];
            3'd6: byte_at = w[55:48];
            3'd7: byte_at = w[63:56];
        endcase
    endfunction

    function signed [7:0] sat_shift(input signed [31:0] v);
        reg signed [31:0] s;
        begin
            s = v >>> CONV_SHIFT;
            if      (s >  127) sat_shift =  8'sd127;
            else if (s < -128) sat_shift = -8'sd128;
            else               sat_shift =  s[7:0];
        end
    endfunction

    reg [9:0] img_word_addr_reg;
    reg [3:0] cw_word_addr_reg;

    reg [7:0] x_byte_lat, w_byte_lat;

    always @(posedge clk) begin
        if (reset) begin
            state          <= S_IDLE;
            busy           <= 1'b0;
            result_tumor   <= 1'b0;
            oc             <= 2'd0;
            py             <= 3'd0;
            px             <= 3'd0;
            j_idx          <= 2'd0;
            i_idx          <= 2'd0;
            ic             <= 2'd0;
            ky             <= 2'd0;
            kx             <= 2'd0;
            acc            <= 32'sd0;
            best           <= 32'sd0;
            bias_val       <= 32'sd0;
            out_word_buf   <= 64'd0;
            out_byte_pos   <= 3'd0;
            out_word_count <= 5'd0;
            fc_idx         <= 8'd0;
            img_word_addr_reg <= 10'd0;
            cw_word_addr_reg  <= 4'd0;
            dmem_re        <= 1'b0;
            dmem_raddr     <= 9'd0;
            dmem_we        <= 1'b0;
            dmem_waddr     <= 9'd0;
            dmem_wdata     <= 64'd0;
            rom_addr       <= 6'd0;
        end else begin
            dmem_re <= 1'b0;
            dmem_we <= 1'b0;

            case (state)
            S_IDLE: begin
                if (start_pulse) begin
                    busy           <= 1'b1;
                    out_word_buf   <= 64'd0;
                    out_byte_pos   <= 3'd0;
                    out_word_count <= 5'd0;
                    oc             <= 2'd0;
                    py             <= 3'd0;
                    px             <= 3'd0;
                    j_idx          <= 2'd0;
                    i_idx          <= 2'd0;
                    ic             <= 2'd0;
                    ky             <= 2'd0;
                    kx             <= 2'd0;
                    fc_idx         <= 8'd0;
                    best           <= 32'sd0;
                    if (mmio_wdata[1:0] == 2'd1) begin
                        rom_addr <= ROM_CONV1_B_BASE;
                        state    <= S_CP_BIAS_WAIT;
                    end else if (mmio_wdata[1:0] == 2'd2) begin
                        rom_addr <= ROM_FC_B_BASE;
                        state    <= S_FC_BIAS_WAIT;
                    end
                end
            end

            S_CP_LOAD_BIAS: begin
                state <= S_CP_BIAS_WAIT;
            end

            S_CP_BIAS_WAIT: begin
                state <= S_CP_BIAS_USE;
            end

            S_CP_BIAS_USE: begin
                bias_val <= oc[0] ? $signed(rom_rdata[63:32]) : $signed(rom_rdata[31:0]);
                best     <= 32'sd0;
                j_idx    <= 2'd0;
                i_idx    <= 2'd0;
                state    <= S_CP_NEW_CONV;
            end

            S_CP_NEW_CONV: begin
                acc <= bias_val;
                ic  <= 2'd0;
                ky  <= 2'd0;
                kx  <= 2'd0;
                if ((cur_oy >= 5'd24) || (cur_ox >= 5'd24)) begin
                    state <= S_CP_FINALIZE;
                end else begin
                    state <= S_CP_ADDR_PRE;
                end
            end

            S_CP_ADDR_PRE: begin
                img_word_addr_reg <= img_word_addr;
                cw_word_addr_reg  <= cw_word_addr;
                state             <= S_CP_MAC_ISSUE;
            end

            S_CP_MAC_ISSUE: begin
                dmem_re    <= 1'b1;
                dmem_raddr <= reg_x_base + img_word_addr_reg[8:0];
                rom_addr   <= ROM_CONV1_W_BASE + {2'd0, cw_word_addr_reg};
                state      <= S_CP_MAC_WAIT;
            end

            S_CP_MAC_WAIT: begin
                state <= S_CP_MAC_DO;
            end

            S_CP_MAC_DO: begin
                x_byte_lat <= byte_at(dmem_rdata, img_byte_pos);
                w_byte_lat <= byte_at(rom_rdata,  cw_byte_pos);
                state      <= S_CP_MAC_ACC;
            end

            S_CP_MAC_ACC: begin
                acc <= acc + s8_to_s32(x_byte_lat) * s8_to_s32(w_byte_lat);
                if (kx != 2'd2) begin
                    kx <= kx + 2'd1;
                    state <= S_CP_ADDR_PRE;
                end else if (ky != 2'd2) begin
                    kx <= 2'd0;
                    ky <= ky + 2'd1;
                    state <= S_CP_ADDR_PRE;
                end else if (ic != 2'd2) begin
                    kx <= 2'd0;
                    ky <= 2'd0;
                    ic <= ic + 2'd1;
                    state <= S_CP_ADDR_PRE;
                end else begin
                    state <= S_CP_FINALIZE;
                end
            end

            S_CP_FINALIZE: begin
                if (acc[31] == 1'b0 && acc > best) begin
                    best <= acc;
                end
                if (i_idx != 2'd3) begin
                    i_idx <= i_idx + 2'd1;
                    state <= S_CP_NEW_CONV;
                end else if (j_idx != 2'd3) begin
                    i_idx <= 2'd0;
                    j_idx <= j_idx + 2'd1;
                    state <= S_CP_NEW_CONV;
                end else begin
                    state <= S_CP_PACK;
                end
            end

            S_CP_PACK: begin
                case (out_byte_pos)
                    3'd0: out_word_buf[ 7: 0] <= sat_shift(best);
                    3'd1: out_word_buf[15: 8] <= sat_shift(best);
                    3'd2: out_word_buf[23:16] <= sat_shift(best);
                    3'd3: out_word_buf[31:24] <= sat_shift(best);
                    3'd4: out_word_buf[39:32] <= sat_shift(best);
                    3'd5: out_word_buf[47:40] <= sat_shift(best);
                    3'd6: out_word_buf[55:48] <= sat_shift(best);
                    3'd7: out_word_buf[63:56] <= sat_shift(best);
                endcase

                if (out_byte_pos == 3'd7) begin
                    state <= S_CP_FLUSH;
                end else begin
                    out_byte_pos <= out_byte_pos + 3'd1;
                    if (px != 3'd5) begin
                        px    <= px + 3'd1;
                        best  <= 32'sd0;
                        j_idx <= 2'd0;
                        i_idx <= 2'd0;
                        state <= S_CP_NEW_CONV;
                    end else if (py != 3'd5) begin
                        px    <= 3'd0;
                        py    <= py + 3'd1;
                        best  <= 32'sd0;
                        j_idx <= 2'd0;
                        i_idx <= 2'd0;
                        state <= S_CP_NEW_CONV;
                    end else if (oc != 2'd3) begin
                        px       <= 3'd0;
                        py       <= 3'd0;
                        oc       <= oc + 2'd1;
                        rom_addr <= next_bias_word_addr;
                        state    <= S_CP_BIAS_WAIT;
                    end else begin
                        state <= S_CP_FLUSH;
                    end
                end
            end

            S_CP_FLUSH: begin
                dmem_we        <= 1'b1;
                dmem_waddr     <= reg_y_base + {4'd0, out_word_count};
                dmem_wdata     <= out_word_buf;
                out_word_buf   <= 64'd0;
                out_byte_pos   <= 3'd0;
                out_word_count <= out_word_count + 5'd1;
                if (oc == 2'd3 && py == 3'd5 && px == 3'd5) begin
                    state <= S_CP_DONE;
                end else begin
                    if (px != 3'd5) begin
                        px    <= px + 3'd1;
                        best  <= 32'sd0;
                        j_idx <= 2'd0;
                        i_idx <= 2'd0;
                        state <= S_CP_NEW_CONV;
                    end else if (py != 3'd5) begin
                        px    <= 3'd0;
                        py    <= py + 3'd1;
                        best  <= 32'sd0;
                        j_idx <= 2'd0;
                        i_idx <= 2'd0;
                        state <= S_CP_NEW_CONV;
                    end else begin
                        px       <= 3'd0;
                        py       <= 3'd0;
                        oc       <= oc + 2'd1;
                        rom_addr <= next_bias_word_addr;
                        state    <= S_CP_BIAS_WAIT;
                    end
                end
            end

            S_CP_DONE: begin
                busy  <= 1'b0;
                state <= S_IDLE;
            end

            S_FC_LOAD_BIAS: begin
                rom_addr <= ROM_FC_B_BASE;
                state    <= S_FC_BIAS_WAIT;
            end

            S_FC_BIAS_WAIT: begin
                state <= S_FC_BIAS_USE;
            end

            S_FC_BIAS_USE: begin
                acc    <= $signed(rom_rdata[31:0]);
                fc_idx <= 8'd0;
                state  <= S_FC_MAC_ISSUE;
            end

            S_FC_MAC_ISSUE: begin
                dmem_re    <= 1'b1;
                dmem_raddr <= reg_x_base + {4'd0, fc_idx[7:3]};
                rom_addr   <= ROM_FC_W_BASE + {1'b0, fcw_word_addr};
                state      <= S_FC_MAC_WAIT;
            end

            S_FC_MAC_WAIT: begin
                state <= S_FC_MAC_DO;
            end

            S_FC_MAC_DO: begin
                x_byte_lat <= byte_at(dmem_rdata, fc_idx[2:0]);
                w_byte_lat <= byte_at(rom_rdata,  fc_idx[2:0]);
                state      <= S_FC_MAC_ACC;
            end

            S_FC_MAC_ACC: begin
                acc <= acc + s8_to_s32(x_byte_lat) * s8_to_s32(w_byte_lat);
                if (fc_idx == 8'd143) begin
                    state <= S_FC_DONE;
                end else begin
                    fc_idx <= fc_idx + 8'd1;
                    state  <= S_FC_MAC_ISSUE;
                end
            end

            S_FC_DONE: begin
                result_tumor <= (~acc[31]) & (|acc[30:0]);
                busy         <= 1'b0;
                state        <= S_IDLE;
            end

            default: state <= S_IDLE;
            endcase
        end
    end

endmodule