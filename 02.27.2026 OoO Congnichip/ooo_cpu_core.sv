// Top-Level Out-of-Order CPU Core for RV32I
// Integrates all components: Fetch, Decode, RS, ROB, RegFile, Execution
// Simple scalar out-of-order processor with Tomasulo-style execution

module ooo_cpu_core (
    input  logic clock,
    input  logic reset
);

    // Parameters
    localparam ROM_ENTRIES = 16;
    localparam ROM_ADDR_WIDTH = 4;
    localparam ROB_ENTRIES = 16;
    localparam ROB_ADDR_WIDTH = 4;
    localparam RS_ENTRIES = 8;
    localparam ARCH_REGS = 32;

    // ========== Fetch Stage Signals ==========
    logic [ROM_ADDR_WIDTH-1:0] rom_addr;
    logic [31:0]               rom_instruction;
    logic [31:0]               fetch_instruction;
    logic                      fetch_valid;
    logic                      fetch_stall;
    logic                      fetch_flush;
    logic [ROM_ADDR_WIDTH-1:0] fetch_flush_pc;

    // ========== Decode Stage Signals ==========
    logic [4:0]                rs1_addr, rs2_addr;
    logic [31:0]               rs1_value, rs2_value;
    logic                      rs1_valid, rs2_valid;
    logic [ROB_ADDR_WIDTH-1:0] rs1_tag, rs2_tag;
    logic                      dispatch_valid;
    logic [3:0]                dispatch_alu_op;
    logic [31:0]               dispatch_src1_value, dispatch_src2_value;
    logic                      dispatch_src1_ready, dispatch_src2_ready;
    logic [ROB_ADDR_WIDTH-1:0] dispatch_src1_tag, dispatch_src2_tag;
    logic [ROB_ADDR_WIDTH-1:0] dispatch_dest_tag;
    logic                      rob_alloc_valid;
    logic [4:0]                rob_dest_reg;
    logic                      rob_dest_valid;
    logic                      rename_valid;
    logic [4:0]                rename_dest_reg;
    logic [ROB_ADDR_WIDTH-1:0] rename_rob_tag;

    // ========== ROB Signals ==========
    logic [ROB_ADDR_WIDTH-1:0] rob_tag;
    logic                      rob_full;
    logic                      commit_valid;
    logic [4:0]                commit_dest_reg;
    logic [31:0]               commit_value;
    logic                      commit_reg_write;
    logic [ROB_ADDR_WIDTH-1:0] commit_rob_tag;  // ROB tag being committed (head pointer)
    logic [ROB_ADDR_WIDTH-1:0] query_tag;
    logic                      query_ready;
    logic [31:0]               query_value;

    // ========== Reservation Station Signals ==========
    logic                      rs_full;
    logic                      issue_valid;
    logic [3:0]                issue_alu_op;
    logic [31:0]               issue_src1_value, issue_src2_value;
    logic [ROB_ADDR_WIDTH-1:0] issue_dest_tag;
    logic                      issue_ready;

    // ========== Execution / CDB Signals ==========
    logic                      cdb_valid;
    logic [ROB_ADDR_WIDTH-1:0] cdb_tag;
    logic [31:0]               cdb_data;

    // ========== Control Signals ==========
    // Stall fetch if decode cannot proceed
    assign fetch_stall = rob_full || rs_full;
    
    // No flush for now (no branches in simple version)
    assign fetch_flush = 1'b0;
    assign fetch_flush_pc = '0;

    // ========== Module Instantiations ==========

    // Instruction ROM
    instruction_rom #(
        .ROM_ENTRIES(ROM_ENTRIES),
        .ROM_ADDR_WIDTH(ROM_ADDR_WIDTH)
    ) i_rom (
        .clock(clock),
        .addr(rom_addr),
        .instruction(rom_instruction)
    );

    // Fetch Unit
    fetch_unit #(
        .ROM_ADDR_WIDTH(ROM_ADDR_WIDTH)
    ) i_fetch (
        .clock(clock),
        .reset(reset),
        .rom_addr(rom_addr),
        .rom_instruction(rom_instruction),
        .fetch_instruction(fetch_instruction),
        .fetch_valid(fetch_valid),
        .stall(fetch_stall),
        .flush(fetch_flush),
        .flush_pc(fetch_flush_pc)
    );

    // Register File with Renaming
    register_file #(
        .ARCH_REGS(ARCH_REGS),
        .ROB_ADDR_WIDTH(ROB_ADDR_WIDTH)
    ) i_regfile (
        .clock(clock),
        .reset(reset),
        .rs1_addr(rs1_addr),
        .rs1_value(rs1_value),
        .rs1_valid(rs1_valid),
        .rs1_tag(rs1_tag),
        .rs2_addr(rs2_addr),
        .rs2_value(rs2_value),
        .rs2_valid(rs2_valid),
        .rs2_tag(rs2_tag),
        .commit_valid(commit_valid && commit_reg_write),
        .commit_dest_reg(commit_dest_reg),
        .commit_value(commit_value),
        .commit_rob_tag(commit_rob_tag),
        .rename_valid(rename_valid),
        .rename_dest_reg(rename_dest_reg),
        .rename_rob_tag(rename_rob_tag),
        .flush(fetch_flush)
    );

    // Reorder Buffer
    reorder_buffer #(
        .ROB_ENTRIES(ROB_ENTRIES),
        .ROB_ADDR_WIDTH(ROB_ADDR_WIDTH),
        .ARCH_REGS(ARCH_REGS)
    ) i_rob (
        .clock(clock),
        .reset(reset),
        .dispatch_valid(rob_alloc_valid),
        .dispatch_dest_reg(rob_dest_reg),
        .dispatch_dest_valid(rob_dest_valid),
        .dispatch_rob_tag(rob_tag),
        .rob_full(rob_full),
        .cdb_valid(cdb_valid),
        .cdb_tag(cdb_tag),
        .cdb_data(cdb_data),
        .commit_valid(commit_valid),
        .commit_dest_reg(commit_dest_reg),
        .commit_value(commit_value),
        .commit_reg_write(commit_reg_write),
        .commit_rob_tag(commit_rob_tag),
        .query_tag(query_tag),
        .query_ready(query_ready),
        .query_value(query_value)
    );

    // Decode Unit
    decode_unit #(
        .ROB_ADDR_WIDTH(ROB_ADDR_WIDTH)
    ) i_decode (
        .clock(clock),
        .reset(reset),
        .instruction(fetch_instruction),
        .instruction_valid(fetch_valid),
        .rs1_addr(rs1_addr),
        .rs1_value(rs1_value),
        .rs1_valid(rs1_valid),
        .rs1_tag(rs1_tag),
        .rs2_addr(rs2_addr),
        .rs2_value(rs2_value),
        .rs2_valid(rs2_valid),
        .rs2_tag(rs2_tag),
        .rob_tag(rob_tag),
        .rob_full(rob_full),
        .dispatch_valid(dispatch_valid),
        .dispatch_alu_op(dispatch_alu_op),
        .dispatch_src1_value(dispatch_src1_value),
        .dispatch_src1_ready(dispatch_src1_ready),
        .dispatch_src1_tag(dispatch_src1_tag),
        .dispatch_src2_value(dispatch_src2_value),
        .dispatch_src2_ready(dispatch_src2_ready),
        .dispatch_src2_tag(dispatch_src2_tag),
        .dispatch_dest_tag(dispatch_dest_tag),
        .rs_full(rs_full),
        .rob_alloc_valid(rob_alloc_valid),
        .rob_dest_reg(rob_dest_reg),
        .rob_dest_valid(rob_dest_valid),
        .rename_valid(rename_valid),
        .rename_dest_reg(rename_dest_reg),
        .rename_rob_tag(rename_rob_tag)
    );

    // Reservation Station
    reservation_station #(
        .RS_ENTRIES(RS_ENTRIES),
        .ROB_ENTRIES(ROB_ENTRIES),
        .RS_ADDR_WIDTH(3),
        .ROB_ADDR_WIDTH(ROB_ADDR_WIDTH)
    ) i_rs (
        .clock(clock),
        .reset(reset),
        .dispatch_valid(dispatch_valid),
        .dispatch_alu_op(dispatch_alu_op),
        .dispatch_src1_value(dispatch_src1_value),
        .dispatch_src1_ready(dispatch_src1_ready),
        .dispatch_src1_tag(dispatch_src1_tag),
        .dispatch_src2_value(dispatch_src2_value),
        .dispatch_src2_ready(dispatch_src2_ready),
        .dispatch_src2_tag(dispatch_src2_tag),
        .dispatch_dest_tag(dispatch_dest_tag),
        .rs_full(rs_full),
        .cdb_valid(cdb_valid),
        .cdb_tag(cdb_tag),
        .cdb_data(cdb_data),
        .issue_valid(issue_valid),
        .issue_alu_op(issue_alu_op),
        .issue_src1_value(issue_src1_value),
        .issue_src2_value(issue_src2_value),
        .issue_dest_tag(issue_dest_tag),
        .issue_ready(issue_ready)
    );

    // Execution Unit
    execution_unit #(
        .ROB_ADDR_WIDTH(ROB_ADDR_WIDTH)
    ) i_exec (
        .clock(clock),
        .reset(reset),
        .issue_valid(issue_valid),
        .issue_alu_op(issue_alu_op),
        .issue_src1_value(issue_src1_value),
        .issue_src2_value(issue_src2_value),
        .issue_dest_tag(issue_dest_tag),
        .issue_ready(issue_ready),
        .cdb_valid(cdb_valid),
        .cdb_tag(cdb_tag),
        .cdb_data(cdb_data)
    );

endmodule