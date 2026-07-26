// 8-N-1 UART transmitter. Assert start for one clock when busy is low.
module uart_tx #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD   = 115200,
    parameter integer CLKS_PER_BIT = CLK_HZ / BAUD
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       start,
    output reg        tx,
    output reg        busy
);

reg [9:0] shift_register;
reg [3:0] bit_index;
reg [15:0] clock_count;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx <= 1'b1;
        busy <= 1'b0;
        shift_register <= 10'h3FF;
        bit_index <= 4'd0;
        clock_count <= 16'd0;
    end
    else if (!busy) begin
        tx <= 1'b1;
        clock_count <= 16'd0;
        bit_index <= 4'd0;
        if (start) begin
            // stop, data[7:0], start; bit zero is transmitted first.
            shift_register <= {1'b1, data, 1'b0};
            tx <= 1'b0;
            busy <= 1'b1;
        end
    end
    else if (clock_count == CLKS_PER_BIT - 1) begin
        clock_count <= 16'd0;
        if (bit_index == 4'd9) begin
            tx <= 1'b1;
            busy <= 1'b0;
        end
        else begin
            shift_register <= {1'b1, shift_register[9:1]};
            tx <= shift_register[1];
            bit_index <= bit_index + 4'd1;
        end
    end
    else
        clock_count <= clock_count + 16'd1;
end

endmodule
