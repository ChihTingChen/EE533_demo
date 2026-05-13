`timescale 1ns / 1ps

module Convertible_FIFO_Mem(
    input clk, reset,

    input  [63:0] in_data,
    input  [7:0]  in_ctrl,
    input         in_wr,
    output        in_rdy,
    output [63:0] out_data,
    output [7:0]  out_ctrl,
    output        out_wr,
    input         out_rdy,

    input         sw_we,
    input  [8:0]  sw_addr,
    input  [63:0] sw_wdata,
    input         sw_fifo_full,

    input         cpu_we,
    input  [8:0]  cpu_addr,
    input  [63:0] cpu_wdata,
    output [71:0] mem_data_out,

    output        FIFO_FULL,
    output        CPU_GO
);

    assign in_rdy   = 1'b1;
    assign out_data = 64'd0;
    assign out_ctrl = 8'd0;
    assign out_wr   = 1'b0;

    reg sw_fifo_full_d;
    always @(posedge clk) sw_fifo_full_d <= sw_fifo_full;
    wire sw_fifo_full_pulse = sw_fifo_full & ~sw_fifo_full_d;

    wire cpu_release = cpu_we && (cpu_addr == 9'h1FF);

    reg [2:0] state;
    localparam S_IDLE         = 0, 
               S_PKT1_HDR     = 1, 
               S_PKT1_PAYLOAD = 2,
               S_WAIT_PKT2    = 3, 
               S_PKT2_HDR     = 4, 
               S_PKT2_PAYLOAD = 5,
               S_CPU_RUN      = 6;

    reg [8:0] wr_addr;
    reg [3:0] hdr_cnt;
    reg [7:0] word_cnt; 
    reg       fifo_full_reg;

    assign FIFO_FULL = fifo_full_reg | sw_fifo_full_pulse;
    assign CPU_GO    = fifo_full_reg | sw_fifo_full_pulse;

    always @(posedge clk) begin
        if (reset || cpu_release) begin
            state         <= S_IDLE;
            fifo_full_reg <= 1'b0;
            wr_addr       <= 9'd3;
            hdr_cnt       <= 4'd0;
            word_cnt      <= 8'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (in_wr) begin
                        state   <= S_PKT1_HDR;
                        hdr_cnt <= 4'd1;
                    end
                end
                S_PKT1_HDR: begin
                    if (in_wr) begin
                        if (hdr_cnt == 4'd6) begin
                            state    <= S_PKT1_PAYLOAD;
                            wr_addr  <= 9'd3; 
                            word_cnt <= 8'd0; 
                        end else begin
                            hdr_cnt <= hdr_cnt + 4'd1;
                        end
                    end
                end
                S_PKT1_PAYLOAD: begin
                    if (in_wr) begin
                        if (word_cnt < 8'd147) begin
                            wr_addr  <= wr_addr + 9'd1;
                            word_cnt <= word_cnt + 8'd1;
                        end
                        if (in_ctrl != 8'd0) begin 
                            state <= S_WAIT_PKT2;
                        end
                    end
                end
                S_WAIT_PKT2: begin
                    if (in_wr) begin
                        state   <= S_PKT2_HDR;
                        hdr_cnt <= 4'd1;
                    end
                end
                S_PKT2_HDR: begin
                    if (in_wr) begin
                        if (hdr_cnt == 4'd6) begin
                            state    <= S_PKT2_PAYLOAD;
                            word_cnt <= 8'd0; 
                        end else begin
                            hdr_cnt <= hdr_cnt + 4'd1;
                        end
                    end
                end
                S_PKT2_PAYLOAD: begin
                    if (in_wr) begin
                        if (word_cnt < 8'd147) begin
                            wr_addr  <= wr_addr + 9'd1;
                            word_cnt <= word_cnt + 8'd1;
                        end
                        if (in_ctrl != 8'd0) begin 
                            state         <= S_CPU_RUN;
                            fifo_full_reg <= 1'b1;
                        end
                    end
                end
                S_CPU_RUN: begin
                end
            endcase
        end
    end

    wire net_we = in_wr && ((state == S_PKT1_PAYLOAD && word_cnt < 8'd147) || 
                            (state == S_PKT2_PAYLOAD && word_cnt < 8'd147));

    wire        wen   = net_we | sw_we | cpu_we;
    wire [8:0]  addrA = net_we ? wr_addr : (sw_we ? sw_addr : cpu_addr);
    wire [71:0] dataA = net_we ? {8'd0, in_data} : (sw_we ? {8'd0, sw_wdata} : {8'd0, cpu_wdata});
    wire [8:0]  addrB = cpu_addr;

    Dual_Port_SRAM sram(
        .clk(clk), .reset(reset), .wen(wen),
        .addrA(addrA), .addrB(addrB), .dataA(dataA), .data_outB(mem_data_out)
    );

endmodule

module Dual_Port_SRAM(
    input         clk, reset, wen,
    input  [8:0]  addrA, addrB,
    input  [71:0] dataA,
    output reg [71:0] data_outB
);
    reg [71:0] memory [0:511];
    always @(posedge clk) begin
        if (wen) memory[addrA] <= dataA;
    end
    always @(posedge clk) begin
        data_outB <= memory[addrB];
    end
endmodule