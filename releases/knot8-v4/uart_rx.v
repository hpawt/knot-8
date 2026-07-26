// 8-N-1 UART receiver. CLKS_PER_BIT is rounded down from CLK_HZ / BAUD.
module uart_rx #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD   = 115200,
    parameter integer CLKS_PER_BIT = CLK_HZ / BAUD
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        data_valid,
    output reg        framing_error
);

localparam [2:0] IDLE  = 3'd0;
localparam [2:0] START = 3'd1;
localparam [2:0] DATA  = 3'd2;
localparam [2:0] STOP  = 3'd3;

reg rx_meta;
reg rx_sync;
reg [2:0] state;
reg [15:0] clock_count;
reg [2:0] bit_index;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_meta <= 1'b1;
        rx_sync <= 1'b1;
    end
    else begin
        rx_meta <= rx;
        rx_sync <= rx_meta;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        clock_count <= 16'd0;
        bit_index <= 3'd0;
        data <= 8'h00;
        data_valid <= 1'b0;
        framing_error <= 1'b0;
    end
    else begin
        data_valid <= 1'b0;
        framing_error <= 1'b0;

        case (state)
            IDLE: begin
                clock_count <= 16'd0;
                bit_index <= 3'd0;
                if (!rx_sync)
                    state <= START;
            end

            START: begin
                if (clock_count == ((CLKS_PER_BIT - 1) / 2)) begin
                    clock_count <= 16'd0;
                    if (!rx_sync)
                        state <= DATA;
                    else
                        state <= IDLE;
                end
                else
                    clock_count <= clock_count + 16'd1;
            end

            DATA: begin
                if (clock_count == CLKS_PER_BIT - 1) begin
                    clock_count <= 16'd0;
                    data[bit_index] <= rx_sync;
                    if (bit_index == 3'd7) begin
                        bit_index <= 3'd0;
                        state <= STOP;
                    end
                    else
                        bit_index <= bit_index + 3'd1;
                end
                else
                    clock_count <= clock_count + 16'd1;
            end

            STOP: begin
                if (clock_count == CLKS_PER_BIT - 1) begin
                    clock_count <= 16'd0;
                    if (rx_sync)
                        data_valid <= 1'b1;
                    else
                        framing_error <= 1'b1;
                    state <= IDLE;
                end
                else
                    clock_count <= clock_count + 16'd1;
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule
