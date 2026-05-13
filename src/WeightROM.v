`timescale 1ns / 1ps

module WeightROM(
    input             clk,
    input      [5:0]  sw_addr,
    input      [63:0] sw_data,
    input             sw_we,
    input      [5:0]  rom_addr,
    output reg [63:0] rom_rdata
);
    reg [63:0] mem [0:63];
    always @(posedge clk) begin
        if (sw_we) mem[sw_addr] <= sw_data;
        rom_rdata <= mem[rom_addr];
    end
endmodule
