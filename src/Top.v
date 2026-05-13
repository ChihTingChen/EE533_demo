`timescale 1ns / 1ps

module Top (
    input         clk,
    input         reset,

    input  [63:0] in_data,
    input  [7:0]  in_ctrl,
    input         in_wr,
    output        in_rdy,
    output [63:0] out_data,
    output [7:0]  out_ctrl,
    output        out_wr,
    input         out_rdy,

    input                                reg_req_in,
    input                                reg_ack_in,
    input                                reg_rd_wr_L_in,
    input  [`UDP_REG_ADDR_WIDTH-1:0]     reg_addr_in,
    input  [`CPCI_NF2_DATA_WIDTH-1:0]    reg_data_in,
    input  [1:0]                         reg_src_in,
    output                               reg_req_out,
    output                               reg_ack_out,
    output                               reg_rd_wr_L_out,
    output [`UDP_REG_ADDR_WIDTH-1:0]     reg_addr_out,
    output [`CPCI_NF2_DATA_WIDTH-1:0]    reg_data_out,
    output [1:0]                         reg_src_out
);

    wire result_tumor;
    wire cpu_halted;
    wire fifo_full;
    wire tu_busy;
    wire FIFO_FULL_w, CPU_GO_w;
    assign fifo_full = FIFO_FULL_w;

    wire [31:0] host_ctrl_reg;
    wire [31:0] host_addr;
    wire [31:0] weight_data_lo;
    wire [31:0] weight_data_hi;
    wire [31:0] weight_addr_ctrl;
    wire [31:0] imem_data_reg;
    wire [31:0] imem_addr_ctrl;
    wire [31:0] host_rdata_high;
    wire [31:0] host_rdata_low;

    reg  weight_trigger_last;
    wire weight_we = weight_addr_ctrl[31] & ~weight_trigger_last;
    reg  imem_trigger_last;
    wire imem_we = imem_addr_ctrl[31] & ~imem_trigger_last;
    
    always @(posedge clk) begin
        if (reset) begin
            weight_trigger_last <= 1'b0;
            imem_trigger_last   <= 1'b0;
        end else begin
            weight_trigger_last <= weight_addr_ctrl[31];
            imem_trigger_last   <= imem_addr_ctrl[31];
        end
    end

    wire cpu_power    = host_ctrl_reg[0];
    wire ai_reset     = reset | (~cpu_power);

    assign host_rdata_low  = {29'd0, cpu_halted, tu_busy, result_tumor};
    assign host_rdata_high = {31'd0, fifo_full};

    generic_regs #( 
      .UDP_REG_SRC_WIDTH   (2),
      .TAG                 (`IDS_BLOCK_ADDR),
      .REG_ADDR_WIDTH      (`IDS_REG_ADDR_WIDTH),
      .NUM_COUNTERS        (0),
      .NUM_SOFTWARE_REGS   (7),
      .NUM_HARDWARE_REGS   (2)   
    ) module_regs (
      .reg_req_in (reg_req_in), .reg_ack_in (reg_ack_in), .reg_rd_wr_L_in (reg_rd_wr_L_in),
      .reg_addr_in (reg_addr_in), .reg_data_in (reg_data_in), .reg_src_in (reg_src_in),
      .reg_req_out (reg_req_out), .reg_ack_out (reg_ack_out), .reg_rd_wr_L_out (reg_rd_wr_L_out),
      .reg_addr_out (reg_addr_out), .reg_data_out (reg_data_out), .reg_src_out (reg_src_out),
      .counter_updates (), .counter_decrement(),
      .software_regs ({imem_addr_ctrl, imem_data_reg, weight_addr_ctrl, weight_data_hi, weight_data_lo, host_addr, host_ctrl_reg}),
      .hardware_regs ({host_rdata_high, host_rdata_low}),
      .clk (clk), .reset (reset)
    );

    wire [5:0]  imem_addr;
    wire [31:0] imem_data;
    InstrROM_async iram (
        .clk(clk), .sw_addr(imem_addr_ctrl[5:0]), .sw_data(imem_data_reg),
        .sw_we(imem_we), .addr(imem_addr), .data(imem_data)
    );

    wire cpu_dmem_re, cpu_dmem_we;
    wire [15:0] cpu_dmem_addr;
    wire [31:0] cpu_dmem_wdata;
    reg  [31:0] cpu_dmem_rdata;

    TinyARM cpu (
        .clk(clk), .reset(ai_reset), .start(FIFO_FULL_w & cpu_halted), .halted(cpu_halted),
        .imem_addr(imem_addr), .imem_data(imem_data), .dmem_re(cpu_dmem_re), .dmem_we(cpu_dmem_we),
        .dmem_addr(cpu_dmem_addr), .dmem_wdata(cpu_dmem_wdata), .dmem_rdata(cpu_dmem_rdata)
    );

    wire cpu_to_dmem = (cpu_dmem_addr[15:9] == 7'b0);
    wire cpu_to_mmio = (cpu_dmem_addr[15:8] == 8'hFF);

    wire tu_dmem_re, tu_dmem_we;
    wire [8:0] tu_dmem_raddr, tu_dmem_waddr;
    wire [63:0] tu_dmem_wdata, tu_dmem_rdata;
    wire [5:0] rom_addr;
    wire [63:0] rom_rdata;
    wire [31:0] mmio_rdata;

    TensorUnit tu (
        .clk(clk), .reset(ai_reset),
        .mmio_we(cpu_dmem_we & cpu_to_mmio), .mmio_waddr(cpu_dmem_addr[3:0]), .mmio_wdata(cpu_dmem_wdata),
        .mmio_raddr(cpu_dmem_addr[3:0]), .mmio_rdata(mmio_rdata),
        .dmem_re(tu_dmem_re), .dmem_raddr(tu_dmem_raddr), .dmem_rdata(tu_dmem_rdata),
        .dmem_we(tu_dmem_we), .dmem_waddr(tu_dmem_waddr), .dmem_wdata(tu_dmem_wdata),
        .rom_addr(rom_addr), .rom_rdata(rom_rdata),
        .busy(tu_busy), .result_tumor(result_tumor)
    );

    WeightROM rom (
        .clk(clk), .sw_addr(weight_addr_ctrl[5:0]),
        .sw_data({weight_data_hi, weight_data_lo}), .sw_we(weight_we),
        .rom_addr(rom_addr), .rom_rdata(rom_rdata)
    );

    wire [8:0]  fifo_addr_in = tu_busy ? (tu_dmem_we ? tu_dmem_waddr : tu_dmem_raddr) : cpu_dmem_addr[8:0];
    wire [63:0] fifo_wdata_in = tu_busy ? tu_dmem_wdata : {32'd0, cpu_dmem_wdata};
    wire [71:0] fifo_data_out;

    Convertible_FIFO_Mem fifo (
        .clk(clk), .reset(reset),
        .in_data(in_data), .in_ctrl(in_ctrl), .in_wr(in_wr), .in_rdy(in_rdy),
        .out_data(out_data), .out_ctrl(out_ctrl), .out_wr(out_wr), .out_rdy(out_rdy),
        .cpu_we(tu_busy ? tu_dmem_we : (cpu_dmem_we & cpu_to_dmem)),
        .cpu_addr(fifo_addr_in), .cpu_wdata(fifo_wdata_in), .mem_data_out(fifo_data_out),
        .FIFO_FULL(FIFO_FULL_w), .CPU_GO(CPU_GO_w)
    );

    assign tu_dmem_rdata = fifo_data_out[63:0];

    always @(*) begin
        if (cpu_to_mmio)      cpu_dmem_rdata = mmio_rdata;
        else if (cpu_to_dmem) cpu_dmem_rdata = fifo_data_out[31:0];
        else                  cpu_dmem_rdata = 32'd0;
    end
endmodule