//=============================================================================
// Module:      board_memory
// Description: Knot-8 synchronous RAM, deterministic data reset, and MMIO
//
// Memory map:
//   0000-0FFF  4 KiB program/data RAM (UART loader writable)
//   8000-BFFF  16 KiB compiler data/tape/stack RAM
//   FF00       LED register (bits 3:0)
//   FF01       buttons ({6'b0, S4_n, S3_n}); pressed buttons read as zero
//   FF02       UART TX data (write when FF03 bit 0 is one)
//   FF03       UART TX status (bit 0: ready)
//   otherwise  reads return zero and writes are ignored
//
// A small LED-counter program is used as the FPGA power-up image. The UART
// loader may overwrite any byte in the 4 KiB program RAM while the CPU is held
// in reset. Reads use a one-clock request/valid handshake so Quartus can infer
// the program memory as an embedded M9K RAM instead of thousands of LUTs.
//=============================================================================

module board_memory #(
    parameter [7:0] DEMO_DELAY_INNER  = 8'hFF,
    parameter [7:0] DEMO_DELAY_MIDDLE = 8'hFF,
    parameter [7:0] DEMO_DELAY_OUTER  = 8'h08,
    // Hardware uses 3FFF. Tests may shorten the scrub without shrinking RAM.
    parameter [13:0] DATA_CLEAR_LAST_ADDRESS = 14'h3FFF
) (
    input  wire        clk,
    input  wire        system_rst_n,
    input  wire        cpu_rst_n,

    input  wire [15:0] addr,
    input  wire [7:0]  write_data,
    output reg  [7:0]  read_data,
    input  wire        read_enable,
    output reg         read_valid,
    input  wire        write_enable,

    input  wire        loader_write_enable,
    input  wire [11:0] loader_write_addr,
    input  wire [7:0]  loader_write_data,
    input  wire        data_clear_request,
    output reg         data_clear_busy,

    input  wire [1:0]  button_n,
    output reg  [3:0]  led_value,

    input  wire        uart_tx_ready,
    output reg  [7:0]  uart_tx_data,
    output reg         uart_tx_start
);

(* ramstyle = "M9K" *) reg [7:0] program_ram [0:4095];
(* ramstyle = "M9K" *) reg [7:0] data_ram [0:16383];
reg [7:0] program_read_data;
reg [7:0] data_read_data;
reg [7:0] io_read_data;
reg [1:0] read_source;
reg [13:0] data_clear_address;
integer init_address;

localparam [1:0] READ_PROGRAM = 2'd0;
localparam [1:0] READ_DATA    = 2'd1;
localparam [1:0] READ_IO      = 2'd2;
localparam [1:0] READ_ZERO    = 2'd3;

// Power-up program:
//   Point IDX at FF00, increment R0, write it to the LEDs, delay, repeat.
// Instructions are stored high byte first.
initial begin
    for (init_address = 0; init_address < 4096;
         init_address = init_address + 1)
        program_ram[init_address] = 8'h00;

    program_ram[12'h000] = 8'hC8; // LOADI_H FF
    program_ram[12'h001] = 8'hFF;
    program_ram[12'h002] = 8'hCC; // LOADI_L 00
    program_ram[12'h003] = 8'h00;
    program_ram[12'h004] = 8'h40; // LOADI R0,00
    program_ram[12'h005] = 8'h00;
    program_ram[12'h006] = 8'hC4; // main: STORE R0,[IDX]
    program_ram[12'h007] = 8'h00;
    program_ram[12'h008] = 8'h41; // LOADI R1,inner
    program_ram[12'h009] = DEMO_DELAY_INNER;
    program_ram[12'h00A] = 8'h42; // LOADI R2,middle
    program_ram[12'h00B] = DEMO_DELAY_MIDDLE;
    program_ram[12'h00C] = 8'h43; // LOADI R3,outer
    program_ram[12'h00D] = DEMO_DELAY_OUTER;
    program_ram[12'h00E] = 8'h49; // delay1: SUBI R1,1
    program_ram[12'h00F] = 8'h01;
    program_ram[12'h010] = 8'hE8; // BRNZ delay1
    program_ram[12'h011] = 8'hFC;
    program_ram[12'h012] = 8'h41; // LOADI R1,inner
    program_ram[12'h013] = DEMO_DELAY_INNER;
    program_ram[12'h014] = 8'h4A; // SUBI R2,1
    program_ram[12'h015] = 8'h01;
    program_ram[12'h016] = 8'hE8; // BRNZ delay1
    program_ram[12'h017] = 8'hF6;
    program_ram[12'h018] = 8'h42; // LOADI R2,middle
    program_ram[12'h019] = DEMO_DELAY_MIDDLE;
    program_ram[12'h01A] = 8'h4B; // SUBI R3,1
    program_ram[12'h01B] = 8'h01;
    program_ram[12'h01C] = 8'hE8; // BRNZ delay1
    program_ram[12'h01D] = 8'hF0;
    program_ram[12'h01E] = 8'h44; // ADDI R0,1
    program_ram[12'h01F] = 8'h01;
    program_ram[12'h020] = 8'hE0; // JUMP_REL main
    program_ram[12'h021] = 8'hE4;
end

// M9K RAM has no practical whole-array reset. A one-byte-per-clock scrubber
// gives reset and program upload deterministic zeroed data/tape/BSS memory
// without turning the 16 KiB array into flip-flops. The CPU is held in reset
// by the board top while data_clear_busy is asserted.
always @(posedge clk or negedge system_rst_n) begin
    if (!system_rst_n) begin
        data_clear_address <= 14'h0000;
        data_clear_busy <= 1'b1;
    end
    else if (data_clear_request && !data_clear_busy) begin
        data_clear_address <= 14'h0000;
        data_clear_busy <= 1'b1;
    end
    else if (data_clear_busy) begin
        if (data_clear_address == DATA_CLEAR_LAST_ADDRESS)
            data_clear_busy <= 1'b0;
        else
            data_clear_address <= data_clear_address + 14'd1;
    end
end

// CPU and loader share a single program-memory write port. The loader is only
// active while the CPU is reset, and receives priority as an extra safeguard.
always @(posedge clk) begin
    if (loader_write_enable)
        program_ram[loader_write_addr] <= loader_write_data;
    else if (write_enable && (addr[15:12] == 4'h0))
        program_ram[addr[11:0]] <= write_data;

    if (data_clear_busy)
        data_ram[data_clear_address] <= 8'h00;
    else if (write_enable && (addr[15:14] == 2'b10))
        data_ram[addr[13:0]] <= write_data;

    // Keep array reads in this clocked process so Quartus recognizes a true
    // synchronous RAM template.
    if (read_enable) begin
        if (addr[15:12] == 4'h0) begin
            program_read_data <= program_ram[addr[11:0]];
            read_source <= READ_PROGRAM;
        end
        else if (addr[15:14] == 2'b10) begin
            data_read_data <= data_ram[addr[13:0]];
            read_source <= READ_DATA;
        end
        else if (addr == 16'hFF00) begin
            io_read_data <= {4'b0000, led_value};
            read_source <= READ_IO;
        end
        else if (addr == 16'hFF01) begin
            io_read_data <= {6'b000000, button_n};
            read_source <= READ_IO;
        end
        else if (addr == 16'hFF02) begin
            io_read_data <= 8'h00;
            read_source <= READ_IO;
        end
        else if (addr == 16'hFF03) begin
            io_read_data <= {7'b0000000, uart_tx_ready};
            read_source <= READ_IO;
        end
        else
            read_source <= READ_ZERO;
    end
end

always @* begin
    case (read_source)
        READ_PROGRAM: read_data = program_read_data;
        READ_DATA:    read_data = data_read_data;
        READ_IO:      read_data = io_read_data;
        default:      read_data = 8'h00;
    endcase
end

always @(posedge clk or negedge cpu_rst_n) begin
    if (!cpu_rst_n)
        read_valid <= 1'b0;
    else
        read_valid <= read_enable;
end

always @(posedge clk or negedge cpu_rst_n) begin
    if (!cpu_rst_n) begin
        led_value <= 4'h0;
        uart_tx_data <= 8'h00;
        uart_tx_start <= 1'b0;
    end
    else begin
        uart_tx_start <= 1'b0;
        if (write_enable && (addr == 16'hFF00))
            led_value <= write_data[3:0];
        if (write_enable && (addr == 16'hFF02) && uart_tx_ready) begin
            uart_tx_data <= write_data;
            uart_tx_start <= 1'b1;
        end
    end
end

endmodule
