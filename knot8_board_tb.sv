`timescale 1ns/1ps

module knot8_board_tb;

reg FPGA_CLK = 1'b0;
reg BUTTON_S4_N = 1'b1;
reg BUTTON_S3_N = 1'b1;
reg BUTTON_S2_N = 1'b0;
reg FPGA_RX = 1'b1;
wire FPGA_TX;
wire [3:0] LED_N;

always #10 FPGA_CLK = ~FPGA_CLK;

knot8_board #(
    .DEMO_DELAY_INNER(8'h02),
    .DEMO_DELAY_MIDDLE(8'h02),
    .DEMO_DELAY_OUTER(8'h01),
    .DATA_CLEAR_LAST_ADDRESS(14'h001F),
    .UART_CLKS_PER_BIT(8)
) dut (
    .FPGA_CLK(FPGA_CLK),
    .BUTTON_S4_N(BUTTON_S4_N),
    .BUTTON_S3_N(BUTTON_S3_N),
    .BUTTON_S2_N(BUTTON_S2_N),
    .FPGA_RX(FPGA_RX),
    .FPGA_TX(FPGA_TX),
    .LED_N(LED_N)
);

integer cycles;
initial begin
    repeat (3) @(posedge FPGA_CLK);
    BUTTON_S2_N = 1'b1;

    cycles = 0;
    while ((dut.led_value == 4'b0000) && (cycles < 1500)) begin
        @(posedge FPGA_CLK);
        cycles = cycles + 1;
    end

    if (dut.led_value !== 4'b0001) begin
        $display("FAIL: CPU demo did not increment LED register, value=%b",
                 dut.led_value);
        $fatal(1);
    end

    BUTTON_S2_N = 1'b0;
    #1;
    if (LED_N !== 4'b1111) begin
        $display("FAIL: reset did not clear LEDs, LED_N=%b", LED_N);
        $fatal(1);
    end

    repeat (3) @(posedge FPGA_CLK);
    BUTTON_S2_N = 1'b1;
    repeat (3) @(posedge FPGA_CLK);

    if (dut.system_rst_n !== 1'b1) begin
        $display("FAIL: synchronized reset did not release");
        $fatal(1);
    end
    cycles = 0;
    while (dut.data_clear_busy && (cycles < 100)) begin
        @(posedge FPGA_CLK);
        cycles = cycles + 1;
    end
    if (dut.data_clear_busy || !dut.cpu_rst_n) begin
        $display("FAIL: data RAM scrub did not release CPU");
        $fatal(1);
    end

    BUTTON_S3_N = 1'b0;
    repeat (3) @(posedge FPGA_CLK);
    if (dut.button_s3_sync[1] !== 1'b0) begin
        $display("FAIL: S3 input synchronizer did not capture press");
        $fatal(1);
    end

    force dut.mem_addr = 16'hFF01;
    force dut.mem_rd_en = 1'b1;
    @(posedge FPGA_CLK);
    force dut.mem_rd_en = 1'b0;
    @(posedge FPGA_CLK);
    #1;
    if (dut.mem_data_in[0] !== 1'b0) begin
        $display("FAIL: button MMIO did not report S3 press");
        $fatal(1);
    end
    release dut.mem_rd_en;
    release dut.mem_addr;

    // The v3 data/tape RAM is a contiguous 16 KiB window.
    force dut.mem_addr = 16'h8000;
    force dut.mem_data_out = 8'h5A;
    force dut.mem_wr_en = 1'b1;
    @(posedge FPGA_CLK);
    @(negedge FPGA_CLK);
    force dut.mem_wr_en = 1'b0;
    force dut.mem_rd_en = 1'b1;
    @(posedge FPGA_CLK);
    @(negedge FPGA_CLK);
    force dut.mem_rd_en = 1'b0;
    @(posedge FPGA_CLK);
    #1;
    if (dut.mem_data_in !== 8'h5A) begin
        $display("FAIL: 16 KiB data RAM readback=%02x", dut.mem_data_in);
        $fatal(1);
    end
    release dut.mem_data_out;
    release dut.mem_wr_en;
    release dut.mem_rd_en;
    release dut.mem_addr;

    // S2 is a deterministic runtime reset: program RAM survives, while the
    // data/tape/BSS window is scrubbed to zero before the CPU restarts.
    BUTTON_S2_N = 1'b0;
    repeat (2) @(posedge FPGA_CLK);
    BUTTON_S2_N = 1'b1;
    cycles = 0;
    while ((dut.data_clear_busy || !dut.system_rst_n) && (cycles < 100)) begin
        @(posedge FPGA_CLK);
        cycles = cycles + 1;
    end
    if (dut.data_clear_busy || !dut.cpu_rst_n) begin
        $display("FAIL: reset scrub did not complete");
        $fatal(1);
    end

    force dut.mem_addr = 16'h8000;
    force dut.mem_rd_en = 1'b1;
    @(posedge FPGA_CLK);
    @(negedge FPGA_CLK);
    force dut.mem_rd_en = 1'b0;
    @(posedge FPGA_CLK);
    #1;
    if (dut.mem_data_in !== 8'h00) begin
        $display("FAIL: reset did not clear data RAM, got=%02x",
                 dut.mem_data_in);
        $fatal(1);
    end
    release dut.mem_rd_en;
    release dut.mem_addr;

    $display("PASS: Knot-8 board, synchronizers, RAM, MMIO and LED polarity");
    $finish;
end

endmodule
