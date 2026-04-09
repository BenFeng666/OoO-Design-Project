`timescale 1ns / 1ps




// ============================================================================
// execution_unit.sv — Single-Cycle Execution Unit
// ============================================================================
// Receives issued instructions from the reservation station, executes
// them in one cycle, and broadcasts results on the Common Data Bus (CDB).
//
// Execution is single-cycle for all supported instruction types.
// The unit accepts an instruction when issue_valid && issue_accept,
// and produces a CDB result on the following clock edge.
//
// Limitation: this execution unit is single-entry and non-pipelined.
// It can accept a new instruction only every other cycle (one cycle
// busy producing CDB output, one cycle idle accepting).  This limits
// peak execution throughput to 0.5 instructions/cycle, which is
// acceptable for this educational single-issue OoO core.
//
// BRANCH RESOLUTION RULE (from decode_unit.sv, STABLE):
//   Branches are resolved using dedicated signed/unsigned comparison
//   logic, NOT the ALU.  The execution unit evaluates the branch
//   condition directly from rs1_val, rs2_val, and funct3.
//
//   funct3  Branch  Comparison
//   000     BEQ     rs1 == rs2
//   001     BNE     rs1 != rs2
//   100     BLT     $signed(rs1) <  $signed(rs2)
//   101     BGE     $signed(rs1) >= $signed(rs2)
//   110     BLTU    rs1 <  rs2
//   111     BGEU    rs1 >= rs2
//
// JAL vs JALR distinction:
//   An explicit `issue_is_jalr` signal (threaded from decode through
//   the RS) distinguishes the two jump types:
//     JAL  target = issue_pc + issue_imm
//     JALR target = (issue_src1_value + issue_imm) & ~32'b1
//   Both write rd = PC + 4 (link address).
//
// Flush behavior:
//   On flush, any pending CDB output is cleared and no new issue is
//   accepted.  This prevents wrong-path instructions from being
//   accepted or broadcast across a flush boundary.
//
// Package dependencies:
//   - alu_pkg    (from alu.sv)         — provides alu_op_t
//   - decode_pkg (from decode_unit.sv) — provides instr_type_t
// ============================================================================

module execution_unit
    import alu_pkg::*;
    import decode_pkg::*;
#(
    parameter int DATA_W    = 32,
    parameter int ROB_DEPTH = 4,
    parameter int TAG_W     = $clog2(ROB_DEPTH)
)(
    input  logic              clk,
    input  logic              rst_n,
    input  logic              flush,          // Clear pending CDB, reject issues

    // --- Issue interface (from reservation station) ---
    input  logic              issue_valid,
    input  alu_op_t           issue_alu_op,
    input  instr_type_t       issue_instr_type,
    input  logic [2:0]        issue_funct3,
    input  logic [DATA_W-1:0] issue_pc,
    input  logic [DATA_W-1:0] issue_imm,
    input  logic              issue_uses_imm,
    input  logic [4:0]        issue_rd_addr,
    input  logic              issue_uses_rd,
    input  logic              issue_is_branch,
    input  logic              issue_is_jump,
    input  logic              issue_is_jalr,
    input  logic [DATA_W-1:0] issue_src1_value,
    input  logic [DATA_W-1:0] issue_src2_value,
    input  logic [TAG_W-1:0]  issue_rob_tag,
    output logic              issue_accept,

    // --- CDB broadcast (to RS + ROB) ---
    output logic              cdb_valid,
    output logic [TAG_W-1:0]  cdb_tag,
    output logic [DATA_W-1:0] cdb_value,
    output logic              cdb_branch_taken,
    output logic [DATA_W-1:0] cdb_branch_target
);

    // ================================================================
    // Execution state
    // ================================================================
    logic busy;

    // Accept a new issue when not busy and not flushing
    assign issue_accept = !busy && !flush;

    // ================================================================
    // ALU instance
    // ================================================================
    logic [DATA_W-1:0] alu_a, alu_b;
    logic [DATA_W-1:0] alu_result;
    logic              alu_zero;
    alu_op_t           alu_op_wire;

    alu u_alu (
        .a      (alu_a),
        .b      (alu_b),
        .op     (alu_op_wire),
        .result (alu_result),
        .zero   (alu_zero)
    );

    // ================================================================
    // ALU operand selection (combinational)
    // ================================================================
    // AUIPC:  alu_a = PC,         alu_b = imm      (ALU_ADD → PC + imm)
    // LUI:    alu_a = don't-care, alu_b = imm      (ALU_PASS_B → imm)
    // ALU:    alu_a = src1,       alu_b = src2      (src2 holds imm if I-type)
    // Branch: ALU not used (don't-care inputs)
    // Jump:   ALU not used (don't-care inputs)
    // ================================================================
    always_comb begin
        alu_op_wire = issue_alu_op;

        case (issue_instr_type)
            ITYPE_AUIPC: begin
                alu_a = issue_pc;
                alu_b = issue_imm;
            end
            ITYPE_LUI: begin
                alu_a = '0;
                alu_b = issue_imm;
            end
            default: begin
                alu_a = issue_src1_value;
                alu_b = issue_src2_value;
            end
        endcase
    end

    // ================================================================
    // Branch comparison logic (dedicated, NOT using ALU)
    // ================================================================
    logic branch_taken;

    always_comb begin
        branch_taken = 1'b0;
        if (issue_is_branch) begin
            case (issue_funct3)
                3'b000:  branch_taken = (issue_src1_value == issue_src2_value);                    // BEQ
                3'b001:  branch_taken = (issue_src1_value != issue_src2_value);                    // BNE
                3'b100:  branch_taken = ($signed(issue_src1_value) <  $signed(issue_src2_value));  // BLT
                3'b101:  branch_taken = ($signed(issue_src1_value) >= $signed(issue_src2_value));  // BGE
                3'b110:  branch_taken = (issue_src1_value <  issue_src2_value);                    // BLTU
                3'b111:  branch_taken = (issue_src1_value >= issue_src2_value);                    // BGEU
                default: branch_taken = 1'b0;
            endcase
        end
    end

    // ================================================================
    // Jump target computation (combinational)
    // ================================================================
    // JAL:  target = PC + imm
    // JALR: target = (rs1 + imm) & ~1
    // Distinguished by the explicit issue_is_jalr signal.
    // ================================================================
    logic [DATA_W-1:0] jump_target;

    always_comb begin
        if (issue_is_jalr) begin
            jump_target = (issue_src1_value + issue_imm) & ~32'b1;
        end else begin
            jump_target = issue_pc + issue_imm;
        end
    end

    // ================================================================
    // Branch target computation (combinational)
    // ================================================================
    logic [DATA_W-1:0] branch_target;
    assign branch_target = issue_pc + issue_imm;

    // ================================================================
    // Result and target selection (combinational)
    // ================================================================
    logic [DATA_W-1:0] exec_result;
    logic              exec_branch_taken;
    logic [DATA_W-1:0] exec_branch_target;

    always_comb begin
        exec_result        = alu_result;
        exec_branch_taken  = 1'b0;
        exec_branch_target = '0;

        case (issue_instr_type)
            ITYPE_ALU, ITYPE_LUI, ITYPE_AUIPC: begin
                exec_result = alu_result;
            end

            ITYPE_BRANCH: begin
                // No rd write (uses_rd = 0).
                // Report branch outcome and target to ROB.
                exec_result        = '0;
                exec_branch_taken  = branch_taken;
                exec_branch_target = branch_target;
            end

            ITYPE_JUMP: begin
                // rd = PC + 4 (link address)
                // branch_target = computed jump destination
                exec_result        = issue_pc + 32'd4;
                exec_branch_taken  = 1'b0;
                exec_branch_target = jump_target;
            end

            ITYPE_HALT: begin
                exec_result = '0;
            end

            default: begin
                // ILLEGAL
                exec_result = '0;
            end
        endcase
    end

    // ================================================================
    // CDB output register (synchronous)
    // ================================================================
    always_ff @(posedge clk) begin
        if (!rst_n || flush) begin
            busy              <= 1'b0;
            cdb_valid         <= 1'b0;
            cdb_tag           <= '0;
            cdb_value         <= '0;
            cdb_branch_taken  <= 1'b0;
            cdb_branch_target <= '0;
        end else begin
            if (issue_valid && issue_accept) begin
                busy              <= 1'b1;
                cdb_valid         <= 1'b1;
                cdb_tag           <= issue_rob_tag;
                cdb_value         <= exec_result;
                cdb_branch_taken  <= exec_branch_taken;
                cdb_branch_target <= exec_branch_target;
            end else begin
                busy              <= 1'b0;
                cdb_valid         <= 1'b0;
            end
        end
    end

endmodule


