//=============================================================================
// Module:      knot8_core
// ISA:         Knot-8 v4
// Description: Compiler- and interpreter-oriented multi-cycle 8-bit CPU
//
// External memory contract:
//   * mem_rd_en is a one-clock read request.
//   * The core waits for mem_read_valid before consuming mem_data_in.
//   * Asynchronous memory may use mem_read_valid = mem_rd_en.
//   * mem_wr_en is a one-clock write request; address/data remain stable for
//     the complete external write cycle.
//   * Instructions are fixed 16-bit words stored high byte first.
//
// Knot-8 v4 retains every RISC8 v1/v2/v3 opcode. CPC/CPCI propagate borrow
// while accumulating equality in a sticky Z flag, so one low-to-high chain
// implements correct 16/32-bit equality and ordering.
//=============================================================================

module knot8_core (
    input  wire        clk,
    input  wire        rst_n,

    output reg  [15:0] mem_addr,
    output reg  [7:0]  mem_data_out,
    input  wire [7:0]  mem_data_in,
    output reg         mem_rd_en,
    input  wire        mem_read_valid,
    output reg         mem_wr_en
);

// Programmer-visible state
reg [7:0]  R0;
reg [7:0]  R1;
reg [7:0]  R2;
reg [7:0]  R3;
reg [15:0] IDX;
reg [15:0] IDY;
reg [15:0] PC;
reg [15:0] SP;
reg [7:0]  FLAG;

localparam integer Z_FLAG = 0;
localparam integer C_FLAG = 1; // carry on add, borrow on subtract
localparam integer N_FLAG = 2;
localparam integer V_FLAG = 3;

// v1-compatible control/stack opcodes
localparam [5:0] OP_NOP       = 6'h00;
localparam [5:0] OP_HALT      = 6'h01;
localparam [5:0] OP_SWAPXY    = 6'h02;
localparam [5:0] OP_RET       = 6'h03;
localparam [5:0] OP_PUSH      = 6'h04;
localparam [5:0] OP_POP       = 6'h05;

// v2 compiler/stack/pointer opcodes
localparam [5:0] OP_ADJSP     = 6'h06;
localparam [5:0] OP_LEASP     = 6'h07;
localparam [5:0] OP_SETIDX_H  = 6'h08;
localparam [5:0] OP_SETIDX_L  = 6'h09;
localparam [5:0] OP_GETIDX_H  = 6'h0A;
localparam [5:0] OP_GETIDX_L  = 6'h0B;
localparam [5:0] OP_LOAD_INC  = 6'h0C;
localparam [5:0] OP_STORE_INC = 6'h0D;
localparam [5:0] OP_PUSHI     = 6'h0E;
localparam [5:0] OP_INC_MEM   = 6'h0F;

// Immediate ALU and compiler memory opcodes
localparam [5:0] OP_LOADI     = 6'h10;
localparam [5:0] OP_ADDI      = 6'h11;
localparam [5:0] OP_SUBI      = 6'h12;
localparam [5:0] OP_ANDI      = 6'h13;
localparam [5:0] OP_ORI       = 6'h14;
localparam [5:0] OP_XORI      = 6'h15;
localparam [5:0] OP_CMPI      = 6'h16;
localparam [5:0] OP_LOADSP    = 6'h17;
localparam [5:0] OP_STORESP   = 6'h18;
localparam [5:0] OP_ADCI      = 6'h19;
localparam [5:0] OP_SBCI      = 6'h1A;
localparam [5:0] OP_LOADX     = 6'h1B;
localparam [5:0] OP_STOREX    = 6'h1C;
localparam [5:0] OP_ADJIDX    = 6'h1D;
localparam [5:0] OP_CPCI      = 6'h1E;

// Register ALU opcodes
localparam [5:0] OP_ADD       = 6'h20;
localparam [5:0] OP_SUB       = 6'h21;
localparam [5:0] OP_AND       = 6'h22;
localparam [5:0] OP_OR        = 6'h23;
localparam [5:0] OP_XOR       = 6'h24;
localparam [5:0] OP_CMP       = 6'h25;
localparam [5:0] OP_MOV       = 6'h26;
localparam [5:0] OP_ADC       = 6'h27;
localparam [5:0] OP_SBC       = 6'h28;
localparam [5:0] OP_SHL       = 6'h29;
localparam [5:0] OP_SHR       = 6'h2A;
localparam [5:0] OP_SAR       = 6'h2B;
localparam [5:0] OP_ROL       = 6'h2C;
localparam [5:0] OP_ROR       = 6'h2D;
localparam [5:0] OP_CPC       = 6'h2E;

// Memory, index, and control-flow opcodes
localparam [5:0] OP_LOAD      = 6'h30;
localparam [5:0] OP_STORE     = 6'h31;
localparam [5:0] OP_LOADI_H   = 6'h32;
localparam [5:0] OP_LOADI_L   = 6'h33;
localparam [5:0] OP_INC_IDX   = 6'h34;
localparam [5:0] OP_DEC_IDX   = 6'h35;
localparam [5:0] OP_JUMP_IDX  = 6'h36;
localparam [5:0] OP_CALL      = 6'h37;
localparam [5:0] OP_JUMP_REL  = 6'h38;
localparam [5:0] OP_BRZ       = 6'h39;
localparam [5:0] OP_BRNZ      = 6'h3A;
localparam [5:0] OP_BRC       = 6'h3B;
localparam [5:0] OP_BRNC      = 6'h3C;
localparam [5:0] OP_BRLT      = 6'h3D;
localparam [5:0] OP_BRGE      = 6'h3E;
localparam [5:0] OP_BRGT      = 6'h3F;

// Multi-cycle state machine. Value 4 for S_EXECUTE remains stable for
// existing debug/test tooling.
localparam [3:0] S_FETCH_HI      = 4'd0;
localparam [3:0] S_FETCH_LO      = 4'd1;
localparam [3:0] S_LATCH_LO      = 4'd2;
localparam [3:0] S_EXECUTE       = 4'd4;
localparam [3:0] S_MEM_ADR_CALC  = 4'd5;
localparam [3:0] S_MEM_READ      = 4'd6;
localparam [3:0] S_MEM_WRITE     = 4'd7;
localparam [3:0] S_STACK_PUSH_LO = 4'd8;
localparam [3:0] S_STACK_POP_LO  = 4'd9;
localparam [3:0] S_STACK_POP_HI  = 4'd10;

reg [3:0] state;
reg [7:0] instruction_hi;
reg [5:0] opcode_pipe;
reg [1:0] wb_reg_pipe;
reg [7:0] imm8_pipe;
reg [7:0] reg_A_pipe;
reg [7:0] reg_B_pipe;
reg [15:0] branch_addr_pipe;
reg [15:0] return_addr_pipe;

wire [7:0] decoded_dest_data =
    (instruction_hi[1:0] == 2'd0) ? R0 :
    (instruction_hi[1:0] == 2'd1) ? R1 :
    (instruction_hi[1:0] == 2'd2) ? R2 : R3;

wire [7:0] decoded_source_data =
    (mem_data_in[7:6] == 2'd0) ? R0 :
    (mem_data_in[7:6] == 2'd1) ? R1 :
    (mem_data_in[7:6] == 2'd2) ? R2 : R3;

wire [15:0] signed_imm16 = {{8{imm8_pipe[7]}}, imm8_pipe};

// One shared arithmetic datapath handles all register/immediate ADD, SUB,
// ADC, SBC, and CMP forms. This avoids synthesizing a separate 9-bit adder
// for every opcode.
wire arithmetic_immediate =
    (opcode_pipe == OP_ADDI) ||
    (opcode_pipe == OP_SUBI) ||
    (opcode_pipe == OP_CMPI) ||
    (opcode_pipe == OP_ADCI) ||
    (opcode_pipe == OP_SBCI) ||
    (opcode_pipe == OP_CPCI);
wire arithmetic_subtract =
    (opcode_pipe == OP_SUB) ||
    (opcode_pipe == OP_CMP) ||
    (opcode_pipe == OP_SBC) ||
    (opcode_pipe == OP_CPC) ||
    (opcode_pipe == OP_SUBI) ||
    (opcode_pipe == OP_CMPI) ||
    (opcode_pipe == OP_SBCI) ||
    (opcode_pipe == OP_CPCI);
wire arithmetic_uses_carry =
    (opcode_pipe == OP_ADC) ||
    (opcode_pipe == OP_SBC) ||
    (opcode_pipe == OP_CPC) ||
    (opcode_pipe == OP_ADCI) ||
    (opcode_pipe == OP_SBCI) ||
    (opcode_pipe == OP_CPCI);
wire [7:0] arithmetic_operand_b =
    arithmetic_immediate ? imm8_pipe : reg_B_pipe;
wire arithmetic_carry_in =
    arithmetic_uses_carry ? FLAG[C_FLAG] : 1'b0;
wire [8:0] arithmetic_add_result =
    {1'b0, reg_A_pipe} + {1'b0, arithmetic_operand_b} +
    {{8{1'b0}}, arithmetic_carry_in};
wire [8:0] arithmetic_sub_result =
    {1'b0, reg_A_pipe} - {1'b0, arithmetic_operand_b} -
    {{8{1'b0}}, arithmetic_carry_in};
wire [8:0] arithmetic_result =
    arithmetic_subtract ? arithmetic_sub_result : arithmetic_add_result;
wire arithmetic_overflow =
    arithmetic_subtract ?
        ((reg_A_pipe[7] ^ arithmetic_operand_b[7]) &
         (reg_A_pipe[7] ^ arithmetic_result[7])) :
        (~(reg_A_pipe[7] ^ arithmetic_operand_b[7]) &
          (reg_A_pipe[7] ^ arithmetic_result[7]));

wire [7:0] shl_result = {reg_A_pipe[6:0], 1'b0};
wire [7:0] shr_result = {1'b0, reg_A_pipe[7:1]};
wire [7:0] sar_result = {reg_A_pipe[7], reg_A_pipe[7:1]};
wire [7:0] rol_result = {reg_A_pipe[6:0], FLAG[C_FLAG]};
wire [7:0] ror_result = {FLAG[C_FLAG], reg_A_pipe[7:1]};

task write_register;
    input [1:0] register_number;
    input [7:0] value;
    begin
        case (register_number)
            2'd0: R0 <= value;
            2'd1: R1 <= value;
            2'd2: R2 <= value;
            2'd3: R3 <= value;
        endcase
    end
endtask

task write_flags;
    input [7:0] result;
    input carry_or_borrow;
    input overflow;
    begin
        FLAG <= {
            4'b0000,
            overflow,
            result[7],
            carry_or_borrow,
            (result == 8'h00)
        };
    end
endtask

// Compare-with-borrow keeps Z sticky across a low-to-high multi-byte compare.
// C, N, and V describe the current, most-significant-so-far byte.
task write_compare_chain_flags;
    input [7:0] result;
    input borrow;
    input overflow;
    begin
        FLAG <= {
            4'b0000,
            overflow,
            result[7],
            borrow,
            FLAG[Z_FLAG] && (result == 8'h00)
        };
    end
endtask

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        R0 <= 8'h00;
        R1 <= 8'h00;
        R2 <= 8'h00;
        R3 <= 8'h00;
        IDX <= 16'h0000;
        IDY <= 16'h0000;
        PC <= 16'h0000;
        // Data RAM is 8000-BFFF. C000 is its conventional one-past-end
        // empty-stack value, so the first push uses BFFF.
        SP <= 16'hC000;
        FLAG <= 8'h00;

        instruction_hi <= 8'h00;
        opcode_pipe <= OP_NOP;
        wb_reg_pipe <= 2'b00;
        imm8_pipe <= 8'h00;
        reg_A_pipe <= 8'h00;
        reg_B_pipe <= 8'h00;
        branch_addr_pipe <= 16'h0000;
        return_addr_pipe <= 16'h0000;
        state <= S_FETCH_HI;

        mem_addr <= 16'h0000;
        mem_data_out <= 8'h00;
        mem_rd_en <= 1'b0;
        mem_wr_en <= 1'b0;
    end
    else begin
        mem_rd_en <= 1'b0;
        mem_wr_en <= 1'b0;

        case (state)
            S_FETCH_HI: begin
                mem_addr <= PC;
                mem_rd_en <= 1'b1;
                state <= S_FETCH_LO;
            end

            S_FETCH_LO: begin
                if (mem_read_valid) begin
                    instruction_hi <= mem_data_in;
                    mem_addr <= PC + 16'd1;
                    mem_rd_en <= 1'b1;
                    state <= S_LATCH_LO;
                end
            end

            // Capture the second byte and decode directly. Removing the old
            // standalone decode state saves one clock from every instruction.
            S_LATCH_LO: begin
                if (mem_read_valid) begin
                    opcode_pipe <= instruction_hi[7:2];
                    wb_reg_pipe <= instruction_hi[1:0];
                    imm8_pipe <= mem_data_in;
                    reg_A_pipe <= decoded_dest_data;
                    reg_B_pipe <= decoded_source_data;
                    return_addr_pipe <= PC + 16'd2;
                    branch_addr_pipe <=
                        PC + 16'd2 + {{8{mem_data_in[7]}}, mem_data_in};
                    state <= S_EXECUTE;
                end
            end

            S_EXECUTE: begin
                case (opcode_pipe)
                    OP_NOP: begin
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_HALT: begin
                        state <= S_EXECUTE;
                    end

                    OP_SWAPXY: begin
                        IDX <= IDY;
                        IDY <= IDX;
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_LOADI: begin
                        write_register(wb_reg_pipe, imm8_pipe);
                        write_flags(imm8_pipe, 1'b0, 1'b0);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_ADDI: begin
                        write_register(wb_reg_pipe, arithmetic_result[7:0]);
                        write_flags(arithmetic_result[7:0],
                                    arithmetic_result[8],
                                    arithmetic_overflow);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_SUBI: begin
                        write_register(wb_reg_pipe, arithmetic_result[7:0]);
                        write_flags(arithmetic_result[7:0],
                                    arithmetic_result[8],
                                    arithmetic_overflow);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_ANDI: begin
                        write_register(wb_reg_pipe,
                                       reg_A_pipe & imm8_pipe);
                        write_flags(reg_A_pipe & imm8_pipe, 1'b0, 1'b0);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_ORI: begin
                        write_register(wb_reg_pipe,
                                       reg_A_pipe | imm8_pipe);
                        write_flags(reg_A_pipe | imm8_pipe, 1'b0, 1'b0);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_XORI: begin
                        write_register(wb_reg_pipe,
                                       reg_A_pipe ^ imm8_pipe);
                        write_flags(reg_A_pipe ^ imm8_pipe, 1'b0, 1'b0);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_CMPI: begin
                        write_flags(arithmetic_result[7:0],
                                    arithmetic_result[8],
                                    arithmetic_overflow);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_ADCI: begin
                        write_register(wb_reg_pipe, arithmetic_result[7:0]);
                        write_flags(arithmetic_result[7:0],
                                    arithmetic_result[8],
                                    arithmetic_overflow);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_SBCI: begin
                        write_register(wb_reg_pipe, arithmetic_result[7:0]);
                        write_flags(arithmetic_result[7:0],
                                    arithmetic_result[8],
                                    arithmetic_overflow);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_CPCI: begin
                        write_compare_chain_flags(arithmetic_result[7:0],
                                                  arithmetic_result[8],
                                                  arithmetic_overflow);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_ADD: begin
                        write_register(wb_reg_pipe, arithmetic_result[7:0]);
                        write_flags(arithmetic_result[7:0],
                                    arithmetic_result[8],
                                    arithmetic_overflow);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_SUB: begin
                        write_register(wb_reg_pipe, arithmetic_result[7:0]);
                        write_flags(arithmetic_result[7:0],
                                    arithmetic_result[8],
                                    arithmetic_overflow);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_AND: begin
                        write_register(wb_reg_pipe,
                                       reg_A_pipe & reg_B_pipe);
                        write_flags(reg_A_pipe & reg_B_pipe, 1'b0, 1'b0);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_OR: begin
                        write_register(wb_reg_pipe,
                                       reg_A_pipe | reg_B_pipe);
                        write_flags(reg_A_pipe | reg_B_pipe, 1'b0, 1'b0);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_XOR: begin
                        write_register(wb_reg_pipe,
                                       reg_A_pipe ^ reg_B_pipe);
                        write_flags(reg_A_pipe ^ reg_B_pipe, 1'b0, 1'b0);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_CMP: begin
                        write_flags(arithmetic_result[7:0],
                                    arithmetic_result[8],
                                    arithmetic_overflow);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_MOV: begin
                        write_register(wb_reg_pipe, reg_B_pipe);
                        write_flags(reg_B_pipe, 1'b0, 1'b0);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_ADC: begin
                        write_register(wb_reg_pipe, arithmetic_result[7:0]);
                        write_flags(arithmetic_result[7:0],
                                    arithmetic_result[8],
                                    arithmetic_overflow);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_SBC: begin
                        write_register(wb_reg_pipe, arithmetic_result[7:0]);
                        write_flags(arithmetic_result[7:0],
                                    arithmetic_result[8],
                                    arithmetic_overflow);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_CPC: begin
                        write_compare_chain_flags(arithmetic_result[7:0],
                                                  arithmetic_result[8],
                                                  arithmetic_overflow);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_SHL: begin
                        write_register(wb_reg_pipe, shl_result);
                        write_flags(shl_result, reg_A_pipe[7],
                                    reg_A_pipe[7] ^ shl_result[7]);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_SHR: begin
                        write_register(wb_reg_pipe, shr_result);
                        write_flags(shr_result, reg_A_pipe[0], 1'b0);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_SAR: begin
                        write_register(wb_reg_pipe, sar_result);
                        write_flags(sar_result, reg_A_pipe[0], 1'b0);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_ROL: begin
                        write_register(wb_reg_pipe, rol_result);
                        write_flags(rol_result, reg_A_pipe[7],
                                    reg_A_pipe[7] ^ rol_result[7]);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_ROR: begin
                        write_register(wb_reg_pipe, ror_result);
                        write_flags(ror_result, reg_A_pipe[0], 1'b0);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_JUMP_REL:
                    begin
                        PC <= branch_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_BRZ: begin
                        PC <= FLAG[Z_FLAG] ?
                              branch_addr_pipe : return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_BRNZ: begin
                        PC <= !FLAG[Z_FLAG] ?
                              branch_addr_pipe : return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_BRC: begin
                        PC <= FLAG[C_FLAG] ?
                              branch_addr_pipe : return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_BRNC: begin
                        PC <= !FLAG[C_FLAG] ?
                              branch_addr_pipe : return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_BRLT: begin
                        PC <= (FLAG[N_FLAG] ^ FLAG[V_FLAG]) ?
                              branch_addr_pipe : return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_BRGE: begin
                        PC <= !(FLAG[N_FLAG] ^ FLAG[V_FLAG]) ?
                              branch_addr_pipe : return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_BRGT: begin
                        PC <= (!FLAG[Z_FLAG] &&
                               !(FLAG[N_FLAG] ^ FLAG[V_FLAG])) ?
                              branch_addr_pipe : return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_ADJSP: begin
                        SP <= SP + signed_imm16;
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_LEASP: begin
                        IDX <= SP + signed_imm16;
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_SETIDX_H: begin
                        IDX[15:8] <= reg_A_pipe;
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_SETIDX_L: begin
                        IDX[7:0] <= reg_A_pipe;
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_GETIDX_H: begin
                        write_register(wb_reg_pipe, IDX[15:8]);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_GETIDX_L: begin
                        write_register(wb_reg_pipe, IDX[7:0]);
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_LOADI_H: begin
                        IDX[15:8] <= imm8_pipe;
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_LOADI_L: begin
                        IDX[7:0] <= imm8_pipe;
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_INC_IDX: begin
                        IDX <= IDX + 16'd1;
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_DEC_IDX: begin
                        IDX <= IDX - 16'd1;
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_ADJIDX: begin
                        IDX <= IDX + signed_imm16;
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end

                    OP_JUMP_IDX: begin
                        PC <= IDX;
                        state <= S_FETCH_HI;
                    end

                    OP_LOAD,
                    OP_STORE,
                    OP_PUSH,
                    OP_POP,
                    OP_CALL,
                    OP_RET,
                    OP_LOADSP,
                    OP_STORESP,
                    OP_LOADX,
                    OP_STOREX,
                    OP_LOAD_INC,
                    OP_STORE_INC,
                    OP_PUSHI,
                    OP_INC_MEM: begin
                        state <= S_MEM_ADR_CALC;
                    end

                    default: begin
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end
                endcase
            end

            S_MEM_ADR_CALC: begin
                case (opcode_pipe)
                    OP_LOAD: begin
                        mem_addr <= IDX;
                        mem_rd_en <= 1'b1;
                        state <= S_MEM_READ;
                    end

                    OP_LOAD_INC: begin
                        mem_addr <= IDX;
                        mem_rd_en <= 1'b1;
                        state <= S_MEM_READ;
                    end

                    OP_INC_MEM: begin
                        mem_addr <= IDX;
                        mem_rd_en <= 1'b1;
                        state <= S_MEM_READ;
                    end

                    OP_LOADSP: begin
                        mem_addr <= SP + signed_imm16;
                        mem_rd_en <= 1'b1;
                        state <= S_MEM_READ;
                    end

                    OP_LOADX: begin
                        mem_addr <= IDX + signed_imm16;
                        mem_rd_en <= 1'b1;
                        state <= S_MEM_READ;
                    end

                    OP_STORE: begin
                        mem_addr <= IDX;
                        mem_data_out <= reg_B_pipe;
                        mem_wr_en <= 1'b1;
                        state <= S_MEM_WRITE;
                    end

                    OP_STORE_INC: begin
                        mem_addr <= IDX;
                        mem_data_out <= reg_A_pipe;
                        mem_wr_en <= 1'b1;
                        IDX <= IDX + 16'd1;
                        state <= S_MEM_WRITE;
                    end

                    OP_STORESP: begin
                        mem_addr <= SP + signed_imm16;
                        mem_data_out <= reg_A_pipe;
                        mem_wr_en <= 1'b1;
                        state <= S_MEM_WRITE;
                    end

                    OP_STOREX: begin
                        mem_addr <= IDX + signed_imm16;
                        mem_data_out <= reg_A_pipe;
                        mem_wr_en <= 1'b1;
                        state <= S_MEM_WRITE;
                    end

                    OP_PUSH: begin
                        SP <= SP - 16'd1;
                        mem_addr <= SP - 16'd1;
                        mem_data_out <= reg_B_pipe;
                        mem_wr_en <= 1'b1;
                        state <= S_MEM_WRITE;
                    end

                    OP_PUSHI: begin
                        SP <= SP - 16'd1;
                        mem_addr <= SP - 16'd1;
                        mem_data_out <= imm8_pipe;
                        mem_wr_en <= 1'b1;
                        state <= S_MEM_WRITE;
                    end

                    OP_POP: begin
                        mem_addr <= SP;
                        mem_rd_en <= 1'b1;
                        state <= S_MEM_READ;
                    end

                    OP_CALL: begin
                        // Descending stack. Store return high byte first, then
                        // low byte, leaving SP pointed at the low byte.
                        SP <= SP - 16'd1;
                        mem_addr <= SP - 16'd1;
                        mem_data_out <= return_addr_pipe[15:8];
                        mem_wr_en <= 1'b1;
                        state <= S_STACK_PUSH_LO;
                    end

                    OP_RET: begin
                        mem_addr <= SP;
                        mem_rd_en <= 1'b1;
                        state <= S_STACK_POP_LO;
                    end

                    default: begin
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end
                endcase
            end

            S_MEM_READ: begin
                if (mem_read_valid) begin
                    case (opcode_pipe)
                        OP_LOAD,
                        OP_LOADSP,
                        OP_LOADX: begin
                            write_register(wb_reg_pipe, mem_data_in);
                        end

                        OP_LOAD_INC: begin
                            write_register(wb_reg_pipe, mem_data_in);
                            IDX <= IDX + 16'd1;
                        end

                        OP_POP: begin
                            write_register(wb_reg_pipe, mem_data_in);
                            SP <= SP + 16'd1;
                        end

                        OP_INC_MEM: begin
                            mem_addr <= IDX;
                            mem_data_out <= mem_data_in + 8'd1;
                            mem_wr_en <= 1'b1;
                            write_flags(
                                mem_data_in + 8'd1,
                                (mem_data_in == 8'hFF),
                                (mem_data_in == 8'h7F)
                            );
                            state <= S_MEM_WRITE;
                        end

                        default: begin
                            // No action.
                        end
                    endcase
                    if (opcode_pipe != OP_INC_MEM) begin
                        PC <= return_addr_pipe;
                        state <= S_FETCH_HI;
                    end
                end
            end

            S_MEM_WRITE: begin
                if (opcode_pipe == OP_CALL)
                    PC <= IDX;
                else
                    PC <= return_addr_pipe;
                state <= S_FETCH_HI;
            end

            S_STACK_PUSH_LO: begin
                SP <= SP - 16'd1;
                mem_addr <= SP - 16'd1;
                mem_data_out <= return_addr_pipe[7:0];
                mem_wr_en <= 1'b1;
                state <= S_MEM_WRITE;
            end

            S_STACK_POP_LO: begin
                if (mem_read_valid) begin
                    PC[7:0] <= mem_data_in;
                    SP <= SP + 16'd1;
                    mem_addr <= SP + 16'd1;
                    mem_rd_en <= 1'b1;
                    state <= S_STACK_POP_HI;
                end
            end

            S_STACK_POP_HI: begin
                if (mem_read_valid) begin
                    PC[15:8] <= mem_data_in;
                    SP <= SP + 16'd1;
                    state <= S_FETCH_HI;
                end
            end

            default: begin
                state <= S_FETCH_HI;
            end
        endcase
    end
end

endmodule
