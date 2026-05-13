`timescale 1ns / 1ps

module TinyARM (
    input         clk,
    input         reset,

    input         start,
    output reg    halted,

    output [5:0]  imem_addr,
    input  [31:0] imem_data,

    output reg        dmem_re,
    output reg        dmem_we,
    output reg [15:0] dmem_addr,
    output reg [31:0] dmem_wdata,
    input      [31:0] dmem_rdata
);
    reg [31:0] regs [0:7];
    reg  [5:0] pc;
    reg        n_flag, z_flag;

    localparam [2:0]
        S_HALT    = 3'd0,
        S_RUN     = 3'd1,
        S_LD_WAIT = 3'd2,
        S_LD_WB   = 3'd3,
        S_FETCH   = 3'd4;

    reg [2:0] state;

    assign imem_addr = pc;
    wire [31:0] ir = imem_data;

    wire [3:0] opcode = ir[31:28];
    wire [3:0] cond   = ir[27:24];
    wire [2:0] rd_idx = ir[22:20];
    wire [2:0] rn_idx = ir[18:16];
    wire [2:0] rm_idx = ir[14:12];
    wire [15:0] imm16 = ir[15: 0];
    wire signed [15:0] imm16_s = imm16;

    wire [31:0] rn_val = regs[rn_idx];
    wire [31:0] rm_val = regs[rm_idx];

    function cond_pass(input [3:0] c, input n, input z);
        case (c)
            4'h0: cond_pass = z;       
            4'h1: cond_pass = ~z;      
            4'h4: cond_pass = n;       
            4'h5: cond_pass = ~n;      
            4'hE: cond_pass = 1'b1;    
            default: cond_pass = 1'b0;
        endcase
    endfunction

    wire cond_ok = cond_pass(cond, n_flag, z_flag);

    reg [31:0] alu_result;
    reg signed [31:0] cmp_val;
    reg upd_flags;
    reg upd_rd;
    reg do_load, do_store;
    reg do_branch;
    reg do_halt;
    reg [15:0] mem_addr_calc;

    always @(*) begin
        alu_result    = 32'd0;
        cmp_val       = 32'sd0;
        upd_flags     = 1'b0;
        upd_rd        = 1'b0;
        do_load       = 1'b0;
        do_store      = 1'b0;
        do_branch     = 1'b0;
        do_halt       = 1'b0;
        mem_addr_calc = 16'd0;

        case (opcode)
            4'h0: begin alu_result = {16'd0, imm16};                                 upd_rd = 1'b1; end
            4'h1: begin alu_result = rn_val + {{16{imm16_s[15]}}, imm16_s};          upd_rd = 1'b1; end
            4'h2: begin alu_result = rn_val + rm_val;                                upd_rd = 1'b1; end
            4'h3: begin alu_result = rn_val - rm_val;                                upd_rd = 1'b1; end
            4'h4: begin cmp_val    = $signed(rn_val) - {{16{imm16_s[15]}}, imm16_s}; upd_flags = 1'b1; end
            4'h5: begin cmp_val    = $signed(rn_val) - $signed(rm_val);              upd_flags = 1'b1; end
            4'h6: begin alu_result = rn_val & {16'd0, imm16};                        upd_rd = 1'b1; end
            4'h7: begin alu_result = rn_val & rm_val;                                upd_rd = 1'b1; end
            4'h8: begin mem_addr_calc = rn_val[15:0] + imm16; do_load  = 1'b1;       end
            4'h9: begin mem_addr_calc = rn_val[15:0] + imm16; do_store = 1'b1;       end
            4'hA: begin do_branch  = 1'b1;                                           end
            4'hF: begin do_halt    = 1'b1;                                           end
            default: ;
        endcase
    end

    // ---- sequential ----
    integer k;
    always @(posedge clk) begin
        if (reset) begin
            state      <= S_HALT;
            halted     <= 1'b1;
            pc         <= 6'd0;
            n_flag     <= 1'b0;
            z_flag     <= 1'b0;
            dmem_re    <= 1'b0;
            dmem_we    <= 1'b0;
            dmem_addr  <= 16'd0;
            dmem_wdata <= 32'd0;
            for (k = 0; k < 8; k = k + 1) regs[k] <= 32'd0;
        end else begin
            dmem_re <= 1'b0;
            dmem_we <= 1'b0;

            case (state)
            S_HALT: begin
                if (start) begin
                    pc     <= 6'd0;
                    halted <= 1'b0;
                    state  <= S_FETCH;
                end
            end

            S_FETCH: begin
                state <= S_RUN;
            end

            S_RUN: begin
                if (!cond_ok) begin
                    pc    <= pc + 6'd1;
                    state <= S_FETCH;
                end else if (do_halt) begin
                    halted <= 1'b1;
                    state  <= S_HALT;
                end else if (do_branch) begin
                    pc    <= pc + 6'd1 + imm16_s[5:0];
                    state <= S_FETCH;
                end else if (do_load) begin
                    dmem_re   <= 1'b1;
                    dmem_addr <= mem_addr_calc;
                    state     <= S_LD_WAIT;
                end else if (do_store) begin
                    dmem_we    <= 1'b1;
                    dmem_addr  <= mem_addr_calc;
                    dmem_wdata <= regs[rd_idx];
                    pc         <= pc + 6'd1;
                    state      <= S_FETCH;
                end else begin
                    if (upd_rd)    regs[rd_idx] <= alu_result;
                    if (upd_flags) begin
                        n_flag <= cmp_val[31];
                        z_flag <= (cmp_val == 32'sd0);
                    end
                    pc    <= pc + 6'd1;
                    state <= S_FETCH;
                end
            end

            S_LD_WAIT: begin
                state <= S_LD_WB;
            end

            S_LD_WB: begin
                regs[rd_idx] <= dmem_rdata;
                pc           <= pc + 6'd1;
                state        <= S_FETCH;
            end

            default: state <= S_HALT;
            endcase
        end
    end

endmodule

module InstrROM_async (
    input             clk,
    input      [5:0]  sw_addr,
    input      [31:0] sw_data,
    input             sw_we,
    input      [5:0]  addr,
    output reg [31:0] data
);
    (* ram_style = "distributed" *)
    reg [31:0] mem [0:63];

    always @(posedge clk) begin
        if (sw_we) mem[sw_addr] <= sw_data;
        data <= mem[addr];
    end
endmodule
