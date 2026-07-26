//=============================================================================
// Knot-8 UART program loader and shared application transmitter
//
// Packet (all multi-byte fields little-endian):
//   4B 38 | length[15:0] | payload[length] | CRC16[15:0]
//    K  8
//
// Legacy 52 38 ("R8") packets are also accepted so existing upload tools can
// recover or update a board that straddles an older architecture transition.
//
// CRC-16/CCITT-FALSE: polynomial 0x1021, initial value 0xFFFF, no reflection,
// calculated over the two length bytes followed by the payload.
//
// Reply: 0x06 ACK on success, 0x15 NAK on invalid length or CRC.
// The CPU is reset after K8/R8 magic is accepted and starts at address 0000
// only after the packet has passed CRC and data RAM scrub has completed.
//=============================================================================

module uart_program_loader (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  rx_data,
    input  wire        rx_valid,

    output reg  [7:0]  tx_data,
    output reg         tx_start,
    input  wire        tx_busy,

    input  wire [7:0]  app_tx_data,
    input  wire        app_tx_start,
    output wire        app_tx_ready,

    input  wire        data_clear_busy,
    output reg         data_clear_request,
    output reg         cpu_hold_reset,
    output reg         write_enable,
    output reg  [11:0] write_addr,
    output reg  [7:0]  write_data
);

localparam [2:0] WAIT_MAGIC = 3'd0;
localparam [2:0] WAIT_8  = 3'd1;
localparam [2:0] LEN_LO  = 3'd2;
localparam [2:0] LEN_HI  = 3'd3;
localparam [2:0] PAYLOAD = 3'd4;
localparam [2:0] CRC_LO  = 3'd5;
localparam [2:0] CRC_HI  = 3'd6;
localparam [2:0] WAIT_CLEAR = 3'd7;

localparam [7:0] MAGIC_K = 8'h4B;
localparam [7:0] MAGIC_R = 8'h52;
localparam [7:0] MAGIC_8 = 8'h38;
localparam [7:0] ACK     = 8'h06;
localparam [7:0] NAK     = 8'h15;

reg [2:0] state;
reg [15:0] length;
reg [11:0] payload_index;
reg [15:0] crc;
reg [7:0] received_crc_low;
reg response_pending;
reg [7:0] response_byte;

assign app_tx_ready =
    (state == WAIT_MAGIC) &&
    !response_pending &&
    !tx_busy &&
    !cpu_hold_reset;

function [15:0] crc16_byte;
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

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= WAIT_MAGIC;
        length <= 16'd0;
        payload_index <= 12'd0;
        crc <= 16'hFFFF;
        received_crc_low <= 8'h00;
        response_pending <= 1'b0;
        response_byte <= 8'h00;
        tx_data <= 8'h00;
        tx_start <= 1'b0;
        cpu_hold_reset <= 1'b0;
        data_clear_request <= 1'b0;
        write_enable <= 1'b0;
        write_addr <= 12'd0;
        write_data <= 8'h00;
    end
    else begin
        tx_start <= 1'b0;
        write_enable <= 1'b0;
        data_clear_request <= 1'b0;

        if (response_pending && !tx_busy) begin
            tx_data <= response_byte;
            tx_start <= 1'b1;
            response_pending <= 1'b0;
        end
        else if (app_tx_start && app_tx_ready) begin
            tx_data <= app_tx_data;
            tx_start <= 1'b1;
        end

        if ((state == WAIT_CLEAR) && !data_clear_busy) begin
            response_byte <= ACK;
            response_pending <= 1'b1;
            cpu_hold_reset <= 1'b0;
            state <= WAIT_MAGIC;
        end

        if (rx_valid) begin
            case (state)
                WAIT_MAGIC: begin
                    if ((rx_data == MAGIC_K) || (rx_data == MAGIC_R))
                        state <= WAIT_8;
                end

                WAIT_8: begin
                    if (rx_data == MAGIC_8) begin
                        cpu_hold_reset <= 1'b1;
                        data_clear_request <= 1'b1;
                        crc <= 16'hFFFF;
                        state <= LEN_LO;
                    end
                    else if ((rx_data != MAGIC_K) &&
                             (rx_data != MAGIC_R))
                        state <= WAIT_MAGIC;
                end

                LEN_LO: begin
                    length[7:0] <= rx_data;
                    crc <= crc16_byte(16'hFFFF, rx_data);
                    state <= LEN_HI;
                end

                LEN_HI: begin
                    length[15:8] <= rx_data;
                    crc <= crc16_byte(crc, rx_data);
                    payload_index <= 12'd0;
                    if (({rx_data, length[7:0]} == 16'd0) ||
                        ({rx_data, length[7:0]} > 16'd4096)) begin
                        response_byte <= NAK;
                        response_pending <= 1'b1;
                        cpu_hold_reset <= 1'b0;
                        state <= WAIT_MAGIC;
                    end
                    else
                        state <= PAYLOAD;
                end

                PAYLOAD: begin
                    write_enable <= 1'b1;
                    write_addr <= payload_index;
                    write_data <= rx_data;
                    crc <= crc16_byte(crc, rx_data);
                    if ({4'b0000, payload_index} + 16'd1 == length)
                        state <= CRC_LO;
                    else
                        payload_index <= payload_index + 12'd1;
                end

                CRC_LO: begin
                    received_crc_low <= rx_data;
                    state <= CRC_HI;
                end

                CRC_HI: begin
                    if ({rx_data, received_crc_low} == crc) begin
                        response_byte <= ACK;
                        if (data_clear_busy) begin
                            response_pending <= 1'b0;
                            state <= WAIT_CLEAR;
                        end
                        else begin
                            response_pending <= 1'b1;
                            cpu_hold_reset <= 1'b0;
                            state <= WAIT_MAGIC;
                        end
                    end
                    else begin
                        response_byte <= NAK;
                        // The RAM now contains an incomplete/corrupt image.
                        // Keep the CPU stopped until a valid retry arrives.
                        cpu_hold_reset <= 1'b1;
                        response_pending <= 1'b1;
                        state <= WAIT_MAGIC;
                    end
                end

                default: state <= WAIT_MAGIC;
            endcase
        end
    end
end

endmodule
