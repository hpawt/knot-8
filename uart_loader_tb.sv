`timescale 1ns/1ps

module uart_loader_tb;

localparam integer CLKS_PER_BIT = 8;

reg FPGA_CLK = 1'b0;
reg BUTTON_S4_N = 1'b1;
reg BUTTON_S3_N = 1'b1;
reg BUTTON_S2_N = 1'b0;
reg FPGA_RX = 1'b1;
wire FPGA_TX;
wire [3:0] LED_N;

reg [7:0] program_bytes [0:31];
reg [15:0] packet_crc;
integer i;
integer timeout;

always #10 FPGA_CLK = ~FPGA_CLK;

knot8_board #(
    .DEMO_DELAY_INNER(8'h02),
    .DEMO_DELAY_MIDDLE(8'h02),
    .DEMO_DELAY_OUTER(8'h01),
    .DATA_CLEAR_LAST_ADDRESS(14'h001F),
    .UART_CLKS_PER_BIT(CLKS_PER_BIT)
) dut (
    .FPGA_CLK(FPGA_CLK),
    .BUTTON_S4_N(BUTTON_S4_N),
    .BUTTON_S3_N(BUTTON_S3_N),
    .BUTTON_S2_N(BUTTON_S2_N),
    .FPGA_RX(FPGA_RX),
    .FPGA_TX(FPGA_TX),
    .LED_N(LED_N)
);

function automatic [15:0] crc16_byte;
    input [15:0] crc_in;
    input [7:0] byte_in;
    integer bit_number;
    reg [15:0] value;
    begin
        value = crc_in ^ {byte_in, 8'h00};
        for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
            if (value[15])
                value = (value << 1) ^ 16'h1021;
            else
                value = value << 1;
        end
        crc16_byte = value;
    end
endfunction

task automatic send_uart_byte(input [7:0] value);
    integer bit_number;
    begin
        FPGA_RX = 1'b0;
        repeat (CLKS_PER_BIT) @(posedge FPGA_CLK);
        for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
            FPGA_RX = value[bit_number];
            repeat (CLKS_PER_BIT) @(posedge FPGA_CLK);
        end
        FPGA_RX = 1'b1;
        repeat (CLKS_PER_BIT) @(posedge FPGA_CLK);
    end
endtask

task automatic send_program(
    input [7:0] led_pattern,
    input bad_crc,
    input legacy_magic
);
    begin
        // LOADI_H FF; LOADI_L 00; LOADI R0,pattern; STORE R0,[IDX]; HALT
        program_bytes[0] = 8'hC8;
        program_bytes[1] = 8'hFF;
        program_bytes[2] = 8'hCC;
        program_bytes[3] = 8'h00;
        program_bytes[4] = 8'h40;
        program_bytes[5] = led_pattern;
        program_bytes[6] = 8'hC4;
        program_bytes[7] = 8'h00;
        program_bytes[8] = 8'h04;
        program_bytes[9] = 8'h00;

        packet_crc = 16'hFFFF;
        packet_crc = crc16_byte(packet_crc, 8'd10);
        packet_crc = crc16_byte(packet_crc, 8'd0);
        for (i = 0; i < 10; i = i + 1)
            packet_crc = crc16_byte(packet_crc, program_bytes[i]);

        send_uart_byte(legacy_magic ? 8'h52 : 8'h4B);
        send_uart_byte(8'h38);
        send_uart_byte(8'd10);
        send_uart_byte(8'd0);
        for (i = 0; i < 10; i = i + 1)
            send_uart_byte(program_bytes[i]);
        send_uart_byte(packet_crc[7:0] ^ {7'd0, bad_crc});
        send_uart_byte(packet_crc[15:8]);
    end
endtask

task automatic send_uart_output_program;
    begin
        // Poll FF03 until the shared transmitter is ready, then write 'K' to
        // FF02. This proves CPU UART output works after the loader ACK.
        program_bytes[0]  = 8'hC8; // LOADI_H FF
        program_bytes[1]  = 8'hFF;
        program_bytes[2]  = 8'hCC; // LOADI_L 03
        program_bytes[3]  = 8'h03;
        program_bytes[4]  = 8'hC0; // wait: LOAD R0,[IDX]
        program_bytes[5]  = 8'h00;
        program_bytes[6]  = 8'h58; // CMPI R0,1
        program_bytes[7]  = 8'h01;
        program_bytes[8]  = 8'hE8; // BRNZ wait (-6 bytes)
        program_bytes[9]  = 8'hFA;
        program_bytes[10] = 8'hCC; // LOADI_L 02
        program_bytes[11] = 8'h02;
        program_bytes[12] = 8'h40; // LOADI R0,'K'
        program_bytes[13] = 8'h4B;
        program_bytes[14] = 8'hC4; // STORE R0,[IDX]
        program_bytes[15] = 8'h00;
        program_bytes[16] = 8'h04; // HALT
        program_bytes[17] = 8'h00;

        packet_crc = 16'hFFFF;
        packet_crc = crc16_byte(packet_crc, 8'd18);
        packet_crc = crc16_byte(packet_crc, 8'd0);
        for (i = 0; i < 18; i = i + 1)
            packet_crc = crc16_byte(packet_crc, program_bytes[i]);

        send_uart_byte(8'h4B);
        send_uart_byte(8'h38);
        send_uart_byte(8'd18);
        send_uart_byte(8'd0);
        for (i = 0; i < 18; i = i + 1)
            send_uart_byte(program_bytes[i]);
        send_uart_byte(packet_crc[7:0]);
        send_uart_byte(packet_crc[15:8]);
    end
endtask

task automatic wait_for_reply(input [7:0] expected);
    begin
        timeout = 0;
        while (!dut.uart_tx_start && timeout < 200) begin
            @(posedge FPGA_CLK);
            timeout = timeout + 1;
        end
        if (!dut.uart_tx_start || dut.uart_tx_data !== expected) begin
            $display("FAIL: expected UART reply %02x, got start=%b data=%02x",
                     expected, dut.uart_tx_start, dut.uart_tx_data);
            $fatal(1);
        end
    end
endtask

initial begin
    repeat (3) @(posedge FPGA_CLK);
    BUTTON_S2_N = 1'b1;
    timeout = 0;
    while ((dut.data_clear_busy || !dut.system_rst_n) && timeout < 100) begin
        @(posedge FPGA_CLK);
        timeout = timeout + 1;
    end
    if (dut.data_clear_busy) begin
        $display("FAIL: initial data RAM scrub did not complete");
        $fatal(1);
    end
    dut.memory.data_ram[0] = 8'hA5;

    send_program(8'h0A, 1'b0, 1'b0);
    wait_for_reply(8'h06);
    if (dut.memory.data_ram[0] !== 8'h00) begin
        $display("FAIL: upload did not scrub data RAM");
        $fatal(1);
    end
    timeout = 0;
    while ((dut.led_value != 4'hA) && (timeout < 300)) begin
        @(posedge FPGA_CLK);
        timeout = timeout + 1;
    end
    if (dut.led_value !== 4'hA) begin
        $display("FAIL: uploaded program did not run, LEDs=%x", dut.led_value);
        $fatal(1);
    end

    // A failed CRC must not execute the partially received image.
    send_program(8'h05, 1'b1, 1'b1);
    wait_for_reply(8'h15);
    repeat (20) @(posedge FPGA_CLK);
    if (!dut.loader_hold_reset || dut.led_value !== 4'h0) begin
        $display("FAIL: bad CRC did not keep CPU reset");
        $fatal(1);
    end

    // A valid retry must recover without cycling board power.
    send_program(8'h05, 1'b0, 1'b0);
    wait_for_reply(8'h06);
    timeout = 0;
    while ((dut.led_value != 4'h5) && (timeout < 300)) begin
        @(posedge FPGA_CLK);
        timeout = timeout + 1;
    end
    if (dut.led_value !== 4'h5) begin
        $display("FAIL: retry did not restart CPU, LEDs=%x", dut.led_value);
        $fatal(1);
    end

    // Upload a program which waits for loader ACK completion and then sends
    // one application byte through the same physical UART transmitter.
    send_uart_output_program();
    wait_for_reply(8'h06);
    @(posedge FPGA_CLK);
    while (dut.uart_tx_start)
        @(posedge FPGA_CLK);
    timeout = 0;
    while (!dut.uart_tx_start && timeout < 1000) begin
        @(posedge FPGA_CLK);
        timeout = timeout + 1;
    end
    if (!dut.uart_tx_start || dut.uart_tx_data !== 8'h4B) begin
        $display("FAIL: expected CPU UART byte 4B, got start=%b data=%02x",
                 dut.uart_tx_start, dut.uart_tx_data);
        $fatal(1);
    end

    $display("PASS: K8/R8 loader, CRC retry, CPU restart and UART TX MMIO");
    $finish;
end

endmodule
