//=============================================================================
// Module:      knot8_board
// Description: Knot-8 v4 top for the DEV190806037 Cyclone 10 LP board
//
// Physical board mapping:
//   FPGA_CLK    PIN_91   50 MHz oscillator
//   BUTTON_S4_N PIN_88   top user button, active low
//   BUTTON_S3_N PIN_89   middle user button, active low
//   BUTTON_S2_N PIN_90   bottom reset button, active low
//   FPGA_RX     PIN_10   data from CH340E USB/UART
//   FPGA_TX     PIN_11   data to CH340E USB/UART
//   LED_N[0]    PIN_101  LED1, active low
//   LED_N[1]    PIN_100  LED2, active low
//   LED_N[2]    PIN_99   LED3, active low
//   LED_N[3]    PIN_98   LED4, active low
//=============================================================================

module knot8_board #(
    parameter [7:0] DEMO_DELAY_INNER  = 8'hFF,
    parameter [7:0] DEMO_DELAY_MIDDLE = 8'hFF,
    parameter [7:0] DEMO_DELAY_OUTER  = 8'h08,
    parameter [13:0] DATA_CLEAR_LAST_ADDRESS = 14'h3FFF,
    parameter integer UART_CLKS_PER_BIT = 434
) (
    input  wire       FPGA_CLK,
    input  wire       BUTTON_S4_N,
    input  wire       BUTTON_S3_N,
    input  wire       BUTTON_S2_N,
    input  wire       FPGA_RX,
    output wire       FPGA_TX,
    output wire [3:0] LED_N
);

wire system_rst_n;
wire cpu_rst_n;
wire [15:0] mem_addr;
wire [7:0]  mem_data_out;
wire [7:0]  mem_data_in;
wire        mem_rd_en;
wire        mem_read_valid;
wire        mem_wr_en;
wire [3:0]  led_value;
wire [7:0]  uart_rx_data;
wire        uart_rx_valid;
wire        uart_rx_framing_error;
wire [7:0]  uart_tx_data;
wire        uart_tx_start;
wire        uart_tx_busy;
wire [7:0]  cpu_uart_tx_data;
wire        cpu_uart_tx_start;
wire        cpu_uart_tx_ready;
wire        loader_hold_reset;
wire        loader_write_enable;
wire [11:0] loader_write_addr;
wire [7:0]  loader_write_data;
wire        data_clear_request;
wire        data_clear_busy;
reg  [1:0]  button_s4_sync;
reg  [1:0]  button_s3_sync;
reg  [4:0]  led_pwm_counter;

// Asynchronous assertion makes the reset button react immediately.  The two
// flip-flops make reset release synchronous to the 50 MHz board clock.
reg [1:0] reset_sync;
always @(posedge FPGA_CLK or negedge BUTTON_S2_N) begin
    if (!BUTTON_S2_N)
        reset_sync <= 2'b00;
    else
        reset_sync <= {reset_sync[0], 1'b1};
end
assign system_rst_n = reset_sync[1];
assign cpu_rst_n =
    system_rst_n & ~loader_hold_reset & ~data_clear_busy;

// User buttons are also asynchronous to FPGA_CLK. Their synchronized levels
// are exposed through MMIO; mechanical debounce can be done in software.
always @(posedge FPGA_CLK or negedge system_rst_n) begin
    if (!system_rst_n) begin
        button_s4_sync <= 2'b11;
        button_s3_sync <= 2'b11;
    end
    else begin
        button_s4_sync <= {button_s4_sync[0], BUTTON_S4_N};
        button_s3_sync <= {button_s3_sync[0], BUTTON_S3_N};
    end
end

uart_rx #(
    .CLK_HZ(50000000),
    .BAUD(115200),
    .CLKS_PER_BIT(UART_CLKS_PER_BIT)
) serial_receiver (
    .clk(FPGA_CLK),
    .rst_n(system_rst_n),
    .rx(FPGA_RX),
    .data(uart_rx_data),
    .data_valid(uart_rx_valid),
    .framing_error(uart_rx_framing_error)
);

uart_tx #(
    .CLK_HZ(50000000),
    .BAUD(115200),
    .CLKS_PER_BIT(UART_CLKS_PER_BIT)
) serial_transmitter (
    .clk(FPGA_CLK),
    .rst_n(system_rst_n),
    .data(uart_tx_data),
    .start(uart_tx_start),
    .tx(FPGA_TX),
    .busy(uart_tx_busy)
);

uart_program_loader loader (
    .clk(FPGA_CLK),
    .rst_n(system_rst_n),
    .rx_data(uart_rx_data),
    .rx_valid(uart_rx_valid),
    .tx_data(uart_tx_data),
    .tx_start(uart_tx_start),
    .tx_busy(uart_tx_busy),
    .app_tx_data(cpu_uart_tx_data),
    .app_tx_start(cpu_uart_tx_start),
    .app_tx_ready(cpu_uart_tx_ready),
    .data_clear_busy(data_clear_busy),
    .data_clear_request(data_clear_request),
    .cpu_hold_reset(loader_hold_reset),
    .write_enable(loader_write_enable),
    .write_addr(loader_write_addr),
    .write_data(loader_write_data)
);

knot8_core cpu (
    .clk(FPGA_CLK),
    .rst_n(cpu_rst_n),
    .mem_addr(mem_addr),
    .mem_data_out(mem_data_out),
    .mem_data_in(mem_data_in),
    .mem_rd_en(mem_rd_en),
    .mem_read_valid(mem_read_valid),
    .mem_wr_en(mem_wr_en)
);

board_memory #(
    .DEMO_DELAY_INNER(DEMO_DELAY_INNER),
    .DEMO_DELAY_MIDDLE(DEMO_DELAY_MIDDLE),
    .DEMO_DELAY_OUTER(DEMO_DELAY_OUTER),
    .DATA_CLEAR_LAST_ADDRESS(DATA_CLEAR_LAST_ADDRESS)
) memory (
    .clk(FPGA_CLK),
    .system_rst_n(system_rst_n),
    .cpu_rst_n(cpu_rst_n),
    .addr(mem_addr),
    .write_data(mem_data_out),
    .read_data(mem_data_in),
    .read_enable(mem_rd_en),
    .read_valid(mem_read_valid),
    .write_enable(mem_wr_en),
    .loader_write_enable(loader_write_enable),
    .loader_write_addr(loader_write_addr),
    .loader_write_data(loader_write_data),
    .data_clear_request(data_clear_request),
    .data_clear_busy(data_clear_busy),
    .button_n({button_s4_sync[1], button_s3_sync[1]}),
    .led_value(led_value),
    .uart_tx_ready(cpu_uart_tx_ready),
    .uart_tx_data(cpu_uart_tx_data),
    .uart_tx_start(cpu_uart_tx_start)
);

// The board LEDs are wired to +3.3 V through resistors and illuminate when
// the FPGA sinks current, hence the inversion. A 4/32 PWM duty cycle reduces
// their average current and makes the unusually bright onboard LEDs pleasant.
always @(posedge FPGA_CLK or negedge system_rst_n) begin
    if (!system_rst_n)
        led_pwm_counter <= 5'd0;
    else
        led_pwm_counter <= led_pwm_counter + 5'd1;
end

assign LED_N = ~({4{led_pwm_counter < 5'd4}} & led_value);

endmodule
