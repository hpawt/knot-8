`timescale 1ns/1ps

module knot8_core_tb;

localparam logic [5:0] OP_NOP      = 6'h00;
localparam logic [5:0] OP_HALT     = 6'h01;
localparam logic [5:0] OP_SWAPXY   = 6'h02;
localparam logic [5:0] OP_RET      = 6'h03;
localparam logic [5:0] OP_PUSH     = 6'h04;
localparam logic [5:0] OP_POP      = 6'h05;
localparam logic [5:0] OP_ADJSP    = 6'h06;
localparam logic [5:0] OP_LEASP    = 6'h07;
localparam logic [5:0] OP_SETIDX_H = 6'h08;
localparam logic [5:0] OP_SETIDX_L = 6'h09;
localparam logic [5:0] OP_GETIDX_H = 6'h0A;
localparam logic [5:0] OP_GETIDX_L = 6'h0B;
localparam logic [5:0] OP_LOAD_INC = 6'h0C;
localparam logic [5:0] OP_STORE_INC= 6'h0D;
localparam logic [5:0] OP_PUSHI    = 6'h0E;
localparam logic [5:0] OP_INC_MEM  = 6'h0F;

localparam logic [5:0] OP_LOADI    = 6'h10;
localparam logic [5:0] OP_ADDI     = 6'h11;
localparam logic [5:0] OP_SUBI     = 6'h12;
localparam logic [5:0] OP_ANDI     = 6'h13;
localparam logic [5:0] OP_ORI      = 6'h14;
localparam logic [5:0] OP_XORI     = 6'h15;
localparam logic [5:0] OP_CMPI     = 6'h16;
localparam logic [5:0] OP_LOADSP   = 6'h17;
localparam logic [5:0] OP_STORESP  = 6'h18;
localparam logic [5:0] OP_ADCI     = 6'h19;
localparam logic [5:0] OP_SBCI     = 6'h1A;
localparam logic [5:0] OP_LOADX    = 6'h1B;
localparam logic [5:0] OP_STOREX   = 6'h1C;
localparam logic [5:0] OP_ADJIDX   = 6'h1D;
localparam logic [5:0] OP_CPCI     = 6'h1E;

localparam logic [5:0] OP_ADD      = 6'h20;
localparam logic [5:0] OP_SUB      = 6'h21;
localparam logic [5:0] OP_AND      = 6'h22;
localparam logic [5:0] OP_OR       = 6'h23;
localparam logic [5:0] OP_XOR      = 6'h24;
localparam logic [5:0] OP_CMP      = 6'h25;
localparam logic [5:0] OP_MOV      = 6'h26;
localparam logic [5:0] OP_ADC      = 6'h27;
localparam logic [5:0] OP_SBC      = 6'h28;
localparam logic [5:0] OP_SHL      = 6'h29;
localparam logic [5:0] OP_SHR      = 6'h2A;
localparam logic [5:0] OP_SAR      = 6'h2B;
localparam logic [5:0] OP_ROL      = 6'h2C;
localparam logic [5:0] OP_ROR      = 6'h2D;
localparam logic [5:0] OP_CPC      = 6'h2E;

localparam logic [5:0] OP_LOAD     = 6'h30;
localparam logic [5:0] OP_STORE    = 6'h31;
localparam logic [5:0] OP_LOADI_H  = 6'h32;
localparam logic [5:0] OP_LOADI_L  = 6'h33;
localparam logic [5:0] OP_INC_IDX  = 6'h34;
localparam logic [5:0] OP_DEC_IDX  = 6'h35;
localparam logic [5:0] OP_JUMP_IDX = 6'h36;
localparam logic [5:0] OP_CALL     = 6'h37;
localparam logic [5:0] OP_JUMP_REL = 6'h38;
localparam logic [5:0] OP_BRZ      = 6'h39;
localparam logic [5:0] OP_BRNZ     = 6'h3A;
localparam logic [5:0] OP_BRC      = 6'h3B;
localparam logic [5:0] OP_BRNC     = 6'h3C;
localparam logic [5:0] OP_BRLT     = 6'h3D;
localparam logic [5:0] OP_BRGE     = 6'h3E;
localparam logic [5:0] OP_BRGT     = 6'h3F;

localparam logic [3:0] S_EXECUTE = 4'd4;

logic clk;
logic rst_n;
wire [15:0] mem_addr;
wire [7:0] mem_data_out;
wire [7:0] mem_data_in;
wire mem_rd_en;
wire mem_read_valid;
wire mem_wr_en;

logic [7:0] memory [0:65535];
integer errors;

knot8_core dut (
    .clk(clk),
    .rst_n(rst_n),
    .mem_addr(mem_addr),
    .mem_data_out(mem_data_out),
    .mem_data_in(mem_data_in),
    .mem_rd_en(mem_rd_en),
    .mem_read_valid(mem_read_valid),
    .mem_wr_en(mem_wr_en)
);

assign mem_data_in = memory[mem_addr];
assign mem_read_valid = mem_rd_en;

initial clk = 1'b0;
always #5 clk = ~clk;

always @(posedge clk) begin
    if (mem_wr_en)
        memory[mem_addr] <= mem_data_out;
end

task automatic clear_memory;
    integer address;
    begin
        for (address = 0; address < 65536; address = address + 1)
            memory[address] = 8'h00;
    end
endtask

task automatic begin_test(input string test_name);
    begin
        $display("");
        $display("TEST: %s", test_name);
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        clear_memory();
    end
endtask

task automatic release_reset;
    begin
        @(negedge clk);
        rst_n = 1'b1;
    end
endtask

task automatic emit_i(
    input integer address,
    input logic [5:0] opcode,
    input logic [1:0] destination,
    input logic [7:0] immediate
);
    begin
        memory[address] = {opcode, destination};
        memory[address + 1] = immediate;
    end
endtask

task automatic emit_r(
    input integer address,
    input logic [5:0] opcode,
    input logic [1:0] destination,
    input logic [1:0] source
);
    begin
        memory[address] = {opcode, destination};
        memory[address + 1] = {source, 6'b000000};
    end
endtask

task automatic emit_o(
    input integer address,
    input logic [5:0] opcode
);
    begin
        memory[address] = {opcode, 2'b00};
        memory[address + 1] = 8'h00;
    end
endtask

task automatic emit_branch(
    input integer address,
    input logic [5:0] opcode,
    input logic [7:0] relative_offset
);
    begin
        memory[address] = {opcode, 2'b00};
        memory[address + 1] = relative_offset;
    end
endtask

task automatic run_until_halt(input integer maximum_cycles);
    integer cycle_count;
    logic halted;
    begin
        halted = 1'b0;
        for (cycle_count = 0;
             cycle_count < maximum_cycles;
             cycle_count = cycle_count + 1) begin
            @(negedge clk);
            if ((dut.state == S_EXECUTE) &&
                (dut.opcode_pipe == OP_HALT)) begin
                halted = 1'b1;
                cycle_count = maximum_cycles;
            end
        end

        if (!halted) begin
            errors = errors + 1;
            $error("CPU did not reach HALT within %0d cycles; PC=%04h state=%0d",
                   maximum_cycles, dut.PC, dut.state);
        end
    end
endtask

task automatic expect8(
    input string item_name,
    input logic [7:0] actual,
    input logic [7:0] expected
);
    begin
        if (actual !== expected) begin
            errors = errors + 1;
            $error("%s: expected %02h, got %02h",
                   item_name, expected, actual);
        end
        else
            $display("  PASS %-18s = %02h", item_name, actual);
    end
endtask

task automatic expect16(
    input string item_name,
    input logic [15:0] actual,
    input logic [15:0] expected
);
    begin
        if (actual !== expected) begin
            errors = errors + 1;
            $error("%s: expected %04h, got %04h",
                   item_name, expected, actual);
        end
        else
            $display("  PASS %-18s = %04h", item_name, actual);
    end
endtask

initial begin
    errors = 0;
    rst_n = 1'b0;
    clear_memory();

    // ---------------------------------------------------------------------
    // Immediate and register ALU operations. Different low bytes on every
    // instruction specifically catch stale IR[7:0] decoding.
    // ---------------------------------------------------------------------
    begin_test("ALU, logic, compare, and write-back");
    emit_i( 0, OP_LOADI, 2'd0, 8'h05);
    emit_i( 2, OP_LOADI, 2'd1, 8'h03);
    emit_r( 4, OP_ADD,   2'd0, 2'd1);
    emit_r( 6, OP_SUB,   2'd0, 2'd1);
    emit_i( 8, OP_ADDI,  2'd0, 8'h0A);
    emit_i(10, OP_SUBI,  2'd0, 8'h05);
    emit_r(12, OP_MOV,   2'd2, 2'd0);
    emit_i(14, OP_LOADI, 2'd3, 8'hF0);
    emit_r(16, OP_AND,   2'd3, 2'd2);
    emit_i(18, OP_ORI,   2'd3, 8'h55);
    emit_i(20, OP_XORI,  2'd3, 8'h0F);
    emit_r(22, OP_OR,    2'd2, 2'd1);
    emit_r(24, OP_XOR,   2'd2, 2'd1);
    emit_i(26, OP_ANDI,  2'd2, 8'h06);
    emit_i(28, OP_CMPI,  2'd2, 8'h00);
    emit_branch(30, OP_BRNZ, 8'h02);
    emit_i(32, OP_ADDI,  2'd2, 8'h01);
    emit_r(34, OP_CMP,   2'd2, 2'd1);
    emit_o(36, OP_HALT);
    release_reset();
    run_until_halt(500);
    expect8("R0", dut.R0, 8'h0A);
    expect8("R1", dut.R1, 8'h03);
    expect8("R2", dut.R2, 8'h01);
    expect8("R3", dut.R3, 8'h5A);
    expect8("FLAG", dut.FLAG, 8'h06);

    // ---------------------------------------------------------------------
    // Signed negative branch offset and BRNZ taken/not-taken behavior.
    // ---------------------------------------------------------------------
    begin_test("signed relative branch loop");
    emit_i(0, OP_LOADI, 2'd0, 8'h03);
    emit_i(2, OP_SUBI,  2'd0, 8'h01);
    emit_branch(4, OP_BRNZ, 8'hFC); // PC + 2 - 4 = address 2
    emit_o(6, OP_HALT);
    release_reset();
    run_until_halt(500);
    expect8("loop result R0", dut.R0, 8'h00);
    expect8("loop FLAG", dut.FLAG, 8'h01);
    expect16("loop halt PC", dut.PC, 16'h0006);

    // ---------------------------------------------------------------------
    // Remaining branch conditions plus unconditional relative jump.
    // ---------------------------------------------------------------------
    begin_test("BRZ, BRNC, BRC, and JUMP_REL");
    emit_i(0, OP_LOADI, 2'd0, 8'h00);
    emit_branch(2, OP_BRZ, 8'h02);
    emit_i(4, OP_LOADI, 2'd1, 8'hEE);
    emit_i(6, OP_LOADI, 2'd1, 8'h11);
    emit_branch(8, OP_BRZ, 8'h02);
    emit_i(10, OP_LOADI, 2'd2, 8'h22);
    emit_branch(12, OP_BRNC, 8'h02);
    emit_i(14, OP_LOADI, 2'd2, 8'hDD);
    emit_i(16, OP_SUBI, 2'd0, 8'h01);
    emit_branch(18, OP_BRC, 8'h02);
    emit_i(20, OP_LOADI, 2'd2, 8'hCC);
    emit_branch(22, OP_JUMP_REL, 8'h02);
    emit_i(24, OP_LOADI, 2'd3, 8'hEE);
    emit_o(26, OP_HALT);
    release_reset();
    run_until_halt(500);
    expect8("branch R0", dut.R0, 8'hFF);
    expect8("branch R1", dut.R1, 8'h11);
    expect8("branch R2", dut.R2, 8'h22);
    expect8("branch R3", dut.R3, 8'h00);
    expect8("branch FLAG", dut.FLAG, 8'h06);

    // ---------------------------------------------------------------------
    // IDX construction, load/store, and IDX increment/decrement.
    // ---------------------------------------------------------------------
    begin_test("indexed memory operations");
    emit_i( 0, OP_LOADI_H, 2'd0, 8'h01);
    emit_i( 2, OP_LOADI_L, 2'd0, 8'h20);
    emit_i( 4, OP_LOADI,   2'd0, 8'hA5);
    emit_r( 6, OP_STORE,   2'd0, 2'd0);
    emit_i( 8, OP_LOAD,    2'd1, 8'h00);
    emit_o(10, OP_INC_IDX);
    emit_i(12, OP_LOADI,   2'd0, 8'h5A);
    emit_r(14, OP_STORE,   2'd0, 2'd0);
    emit_i(16, OP_LOAD,    2'd2, 8'h00);
    emit_o(18, OP_DEC_IDX);
    emit_i(20, OP_LOAD,    2'd3, 8'h00);
    emit_o(22, OP_HALT);
    release_reset();
    run_until_halt(500);
    expect8("memory[0120]", memory[16'h0120], 8'hA5);
    expect8("memory[0121]", memory[16'h0121], 8'h5A);
    expect8("loaded R1", dut.R1, 8'hA5);
    expect8("loaded R2", dut.R2, 8'h5A);
    expect8("loaded R3", dut.R3, 8'hA5);
    expect16("IDX", dut.IDX, 16'h0120);

    // ---------------------------------------------------------------------
    // Byte stack ordering and SP balance.
    // ---------------------------------------------------------------------
    begin_test("PUSH and POP");
    emit_i(0, OP_LOADI, 2'd0, 8'h12);
    emit_r(2, OP_PUSH,  2'd0, 2'd0);
    emit_i(4, OP_LOADI, 2'd0, 8'h34);
    emit_r(6, OP_PUSH,  2'd0, 2'd0);
    emit_i(8, OP_POP,   2'd1, 8'h00);
    emit_i(10, OP_POP,  2'd2, 8'h00);
    emit_o(12, OP_HALT);
    release_reset();
    run_until_halt(500);
    expect8("popped R1", dut.R1, 8'h34);
    expect8("popped R2", dut.R2, 8'h12);
    expect16("balanced SP", dut.SP, 16'hC000);

    // ---------------------------------------------------------------------
    // Absolute IDX jump, NOP, CALL, and RET. The return address has a
    // non-equal high/low byte if the old RET bug corrupts it, causing timeout.
    // ---------------------------------------------------------------------
    begin_test("JUMP_IDX, CALL, RET, and NOP");
    emit_i(16'h0000, OP_LOADI_H, 2'd0, 8'h00);
    emit_i(16'h0002, OP_LOADI_L, 2'd0, 8'h20);
    emit_o(16'h0004, OP_JUMP_IDX);
    emit_i(16'h0006, OP_LOADI, 2'd0, 8'hEE);

    emit_i(16'h0020, OP_LOADI,   2'd0, 8'h05);
    emit_i(16'h0022, OP_LOADI_H, 2'd0, 8'h00);
    emit_i(16'h0024, OP_LOADI_L, 2'd0, 8'h40);
    emit_o(16'h0026, OP_CALL);
    emit_o(16'h0028, OP_NOP);
    emit_i(16'h002A, OP_ADDI, 2'd0, 8'h01);
    emit_o(16'h002C, OP_HALT);

    emit_i(16'h0040, OP_ADDI, 2'd0, 8'h02);
    emit_o(16'h0042, OP_RET);
    release_reset();
    run_until_halt(1000);
    expect8("call result R0", dut.R0, 8'h08);
    expect16("call halt PC", dut.PC, 16'h002C);
    expect16("call IDX", dut.IDX, 16'h0040);
    expect16("call balanced SP", dut.SP, 16'hC000);

    // ---------------------------------------------------------------------
    // Compiler stack-frame primitives, signed offsets, and IDX transfer.
    // ---------------------------------------------------------------------
    begin_test("v2 stack frame and pointer transfer");
    emit_i( 0, OP_PUSHI,    2'd0, 8'h12);
    emit_i( 2, OP_PUSHI,    2'd0, 8'h34);
    emit_i( 4, OP_ADJSP,    2'd0, 8'hFC); // allocate four bytes
    emit_i( 6, OP_LOADI,    2'd0, 8'hA5);
    emit_i( 8, OP_STORESP,  2'd0, 8'h01);
    emit_i(10, OP_LOADSP,   2'd1, 8'h01);
    emit_i(12, OP_LEASP,    2'd0, 8'h01);
    emit_i(14, OP_GETIDX_H, 2'd2, 8'h00);
    emit_i(16, OP_GETIDX_L, 2'd3, 8'h00);
    emit_i(18, OP_LOADI,    2'd0, 8'h80);
    emit_i(20, OP_SETIDX_H, 2'd0, 8'h00);
    emit_i(22, OP_LOADI,    2'd0, 8'h10);
    emit_i(24, OP_SETIDX_L, 2'd0, 8'h00);
    emit_i(26, OP_LOADI,    2'd0, 8'h5A);
    emit_i(28, OP_STOREX,   2'd0, 8'h02);
    emit_i(30, OP_LOADX,    2'd1, 8'h02);
    emit_i(32, OP_ADJIDX,   2'd0, 8'hFE);
    emit_i(34, OP_ADJSP,    2'd0, 8'h04);
    emit_i(36, OP_POP,      2'd0, 8'h00);
    emit_i(38, OP_POP,      2'd3, 8'h00);
    emit_o(40, OP_HALT);
    release_reset();
    run_until_halt(1000);
    expect8("stack local", memory[16'hBFFB], 8'hA5);
    expect8("LOADX R1", dut.R1, 8'h5A);
    expect8("LEASP high R2", dut.R2, 8'hBF);
    expect8("popped R0", dut.R0, 8'h34);
    expect8("popped R3", dut.R3, 8'h12);
    expect8("data[8012]", memory[16'h8012], 8'h5A);
    expect16("adjusted IDX", dut.IDX, 16'h800E);
    expect16("restored SP", dut.SP, 16'hC000);

    // ---------------------------------------------------------------------
    // Knot-8 v3 keeps two independent 16-bit pointers. SWAPXY changes which
    // one is active without spending four general-register transfers.
    // INC_MEM performs the tp2b/C-friendly byte read-modify-write and flags.
    // ---------------------------------------------------------------------
    begin_test("v3 dual pointer and memory increment");
    emit_i( 0, OP_LOADI_H, 2'd0, 8'h80);
    emit_i( 2, OP_LOADI_L, 2'd0, 8'h10);
    emit_o( 4, OP_SWAPXY);
    emit_i( 6, OP_LOADI_H, 2'd0, 8'h80);
    emit_i( 8, OP_LOADI_L, 2'd0, 8'h20);
    emit_o(10, OP_SWAPXY);
    emit_o(12, OP_INC_MEM);
    emit_o(14, OP_SWAPXY);
    emit_o(16, OP_INC_MEM);
    emit_o(18, OP_HALT);
    memory[16'h8010] = 8'hFF;
    memory[16'h8020] = 8'h7F;
    release_reset();
    run_until_halt(500);
    expect8("INC_MEM wrap", memory[16'h8010], 8'h00);
    expect8("INC_MEM signed", memory[16'h8020], 8'h80);
    expect16("active IDX", dut.IDX, 16'h8020);
    expect16("saved IDY", dut.IDY, 16'h8010);
    expect8("INC_MEM FLAG", dut.FLAG, 8'h0C);

    // ---------------------------------------------------------------------
    // Post-increment memory primitives used by array/string loops.
    // ---------------------------------------------------------------------
    begin_test("v2 post-increment memory");
    emit_i( 0, OP_LOADI_H,  2'd0, 8'h02);
    emit_i( 2, OP_LOADI_L,  2'd0, 8'h00);
    emit_i( 4, OP_LOADI,    2'd0, 8'h11);
    emit_i( 6, OP_LOADI,    2'd1, 8'h22);
    emit_i( 8, OP_STORE_INC,2'd0, 8'h00);
    emit_i(10, OP_STORE_INC,2'd1, 8'h00);
    emit_i(12, OP_LOADI_L,  2'd0, 8'h00);
    emit_i(14, OP_LOAD_INC, 2'd2, 8'h00);
    emit_i(16, OP_LOAD_INC, 2'd3, 8'h00);
    emit_o(18, OP_HALT);
    release_reset();
    run_until_halt(500);
    expect8("postinc memory 0", memory[16'h0200], 8'h11);
    expect8("postinc memory 1", memory[16'h0201], 8'h22);
    expect8("postinc load R2", dut.R2, 8'h11);
    expect8("postinc load R3", dut.R3, 8'h22);
    expect16("postinc IDX", dut.IDX, 16'h0202);

    // ---------------------------------------------------------------------
    // Carry/borrow propagation gives the compiler efficient 16-bit math.
    // ---------------------------------------------------------------------
    begin_test("v2 ADC/SBC 16-bit arithmetic");
    emit_i( 0, OP_LOADI, 2'd0, 8'hFF);
    emit_i( 2, OP_LOADI, 2'd1, 8'h00);
    emit_i( 4, OP_LOADI, 2'd2, 8'h01);
    emit_i( 6, OP_LOADI, 2'd3, 8'h00);
    emit_r( 8, OP_ADD,   2'd0, 2'd2);
    emit_r(10, OP_ADC,   2'd1, 2'd3);
    emit_r(12, OP_SUB,   2'd0, 2'd2);
    emit_r(14, OP_SBC,   2'd1, 2'd3);
    emit_i(16, OP_LOADI, 2'd2, 8'hFF);
    emit_i(18, OP_ADDI,  2'd2, 8'h01);
    emit_i(20, OP_ADCI,  2'd3, 8'h00);
    emit_i(22, OP_SUBI,  2'd2, 8'h01);
    emit_i(24, OP_SBCI,  2'd3, 8'h00);
    emit_o(26, OP_HALT);
    release_reset();
    run_until_halt(500);
    expect8("register math low", dut.R0, 8'hFF);
    expect8("register math high", dut.R1, 8'h00);
    expect8("immediate math low", dut.R2, 8'hFF);
    expect8("immediate math high", dut.R3, 8'h00);
    expect8("ADC/SBC FLAG", dut.FLAG, 8'h01);

    // ---------------------------------------------------------------------
    // One-bit shifts and carry-chain rotates.
    // ---------------------------------------------------------------------
    begin_test("v2 shifts and rotates");
    emit_i( 0, OP_LOADI, 2'd0, 8'h81);
    emit_i( 2, OP_SHL,   2'd0, 8'h00);
    emit_i( 4, OP_ROL,   2'd0, 8'h00);
    emit_i( 6, OP_SHR,   2'd0, 8'h00);
    emit_i( 8, OP_ROR,   2'd0, 8'h00);
    emit_i(10, OP_LOADI, 2'd1, 8'h81);
    emit_i(12, OP_SAR,   2'd1, 8'h00);
    emit_o(14, OP_HALT);
    release_reset();
    run_until_halt(500);
    expect8("rotate roundtrip R0", dut.R0, 8'h81);
    expect8("arithmetic shift R1", dut.R1, 8'hC0);
    expect8("shift FLAG", dut.FLAG, 8'h06);

    // ---------------------------------------------------------------------
    // N/V flags and signed comparisons, including overflow edge cases.
    // ---------------------------------------------------------------------
    begin_test("v2 signed branches");
    emit_i( 0, OP_LOADI, 2'd0, 8'h80); // -128
    emit_i( 2, OP_CMPI,  2'd0, 8'h01);
    emit_branch( 4, OP_BRLT, 8'h02);
    emit_i( 6, OP_LOADI, 2'd1, 8'hEE);
    emit_i( 8, OP_LOADI, 2'd1, 8'h11);
    emit_i(10, OP_LOADI, 2'd0, 8'h7F); // +127
    emit_i(12, OP_CMPI,  2'd0, 8'hFF); // compare against -1
    emit_branch(14, OP_BRGE, 8'h02);
    emit_i(16, OP_LOADI, 2'd2, 8'hEE);
    emit_i(18, OP_LOADI, 2'd2, 8'h22);
    emit_i(20, OP_LOADI, 2'd0, 8'h01);
    emit_i(22, OP_CMPI,  2'd0, 8'h00);
    emit_branch(24, OP_BRGT, 8'h02);
    emit_i(26, OP_LOADI, 2'd3, 8'hEE);
    emit_i(28, OP_LOADI, 2'd3, 8'h33);
    emit_o(30, OP_HALT);
    release_reset();
    run_until_halt(500);
    expect8("signed BRLT", dut.R1, 8'h11);
    expect8("signed BRGE", dut.R2, 8'h22);
    expect8("signed BRGT", dut.R3, 8'h33);

    // ---------------------------------------------------------------------
    // v4 compare-with-borrow carries both borrow and whole-value equality
    // across 16/32-bit low-to-high comparisons.
    // ---------------------------------------------------------------------
    begin_test("v4 16-bit compare chain");
    emit_i( 0, OP_LOADI, 2'd0, 8'h00); // A low
    emit_i( 2, OP_LOADI, 2'd1, 8'hFF); // B low
    emit_i( 4, OP_LOADI, 2'd2, 8'h80); // A high: -32768
    emit_i( 6, OP_LOADI, 2'd3, 8'h7F); // B high: +32767
    emit_r( 8, OP_CMP,   2'd0, 2'd1);
    emit_r(10, OP_CPC,   2'd2, 2'd3);
    emit_branch(12, OP_BRLT, 8'h04);
    emit_i(14, OP_LOADI, 2'd0, 8'hEE);
    emit_branch(16, OP_JUMP_REL, 8'h02);
    emit_i(18, OP_LOADI, 2'd0, 8'h11);
    emit_o(20, OP_HALT);
    release_reset();
    run_until_halt(500);
    expect8("16-bit signed less", dut.R0, 8'h11);

    begin_test("v4 sticky equality and 32-bit zero");
    emit_i( 0, OP_LOADI, 2'd0, 8'h01);
    emit_i( 2, OP_LOADI, 2'd1, 8'h00);
    emit_i( 4, OP_LOADI, 2'd2, 8'h00);
    emit_i( 6, OP_LOADI, 2'd3, 8'h00);
    emit_i( 8, OP_CMPI,  2'd0, 8'h00);
    emit_i(10, OP_CPCI,  2'd1, 8'h00);
    emit_i(12, OP_CPCI,  2'd2, 8'h00);
    emit_i(14, OP_CPCI,  2'd3, 8'h00);
    emit_branch(16, OP_BRNZ, 8'h04);
    emit_i(18, OP_LOADI, 2'd3, 8'hEE);
    emit_branch(20, OP_JUMP_REL, 8'h02);
    emit_i(22, OP_LOADI, 2'd3, 8'h22);
    emit_o(24, OP_HALT);
    release_reset();
    run_until_halt(500);
    expect8("32-bit nonzero", dut.R3, 8'h22);

    // ---------------------------------------------------------------------
    // Concrete C ABI frame: right-to-left argument bytes, two-byte return
    // address, callee locals, 16-bit return value, and caller cleanup.
    // ---------------------------------------------------------------------
    begin_test("v2 C calling convention frame");
    emit_i(16'h0000, OP_PUSHI,   2'd0, 8'h12); // arg high
    emit_i(16'h0002, OP_PUSHI,   2'd0, 8'h34); // arg low
    emit_i(16'h0004, OP_LOADI_H, 2'd0, 8'h00);
    emit_i(16'h0006, OP_LOADI_L, 2'd0, 8'h40);
    emit_o(16'h0008, OP_CALL);
    emit_i(16'h000A, OP_ADJSP,   2'd0, 8'h02); // caller removes arg
    emit_o(16'h000C, OP_HALT);

    emit_i(16'h0040, OP_ADJSP,   2'd0, 8'hFE); // two-byte frame
    emit_i(16'h0042, OP_LOADSP,  2'd0, 8'h04); // arg low
    emit_i(16'h0044, OP_LOADSP,  2'd1, 8'h05); // arg high
    emit_i(16'h0046, OP_ADDI,    2'd0, 8'h01);
    emit_i(16'h0048, OP_ADCI,    2'd1, 8'h00);
    emit_i(16'h004A, OP_STORESP, 2'd0, 8'h00);
    emit_i(16'h004C, OP_STORESP, 2'd1, 8'h01);
    emit_i(16'h004E, OP_LOADSP,  2'd2, 8'h00);
    emit_i(16'h0050, OP_LOADSP,  2'd3, 8'h01);
    emit_i(16'h0052, OP_ADJSP,   2'd0, 8'h02);
    emit_o(16'h0054, OP_RET);
    release_reset();
    run_until_halt(1500);
    expect8("ABI return low", dut.R2, 8'h35);
    expect8("ABI return high", dut.R3, 8'h12);
    expect16("ABI balanced SP", dut.SP, 16'hC000);

    // ---------------------------------------------------------------------
    // Undefined opcodes are deliberately specified as NOP.
    // ---------------------------------------------------------------------
    begin_test("undefined opcode recovery");
    emit_i(0, 6'h1F, 2'd3, 8'hA5);
    emit_i(2, OP_LOADI, 2'd0, 8'h77);
    emit_o(4, OP_HALT);
    release_reset();
    run_until_halt(200);
    expect8("post-illegal R0", dut.R0, 8'h77);
    expect16("post-illegal PC", dut.PC, 16'h0004);

    if (errors == 0) begin
        $display("");
        $display("ALL TESTS PASSED");
        $finish;
    end
    else begin
        $fatal(1, "%0d test failure(s)", errors);
    end
end

endmodule
