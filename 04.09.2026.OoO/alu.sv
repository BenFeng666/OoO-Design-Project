`timescale 1ns / 1ps




// ============================================================================
// alu.sv — RV32I Arithmetic Logic Unit
// ============================================================================
// Pure combinational ALU for the RV32I OoO educational CPU.
// Supports all integer arithmetic/logic operations in the base ISA.
// No state, no clock — instantiated inside the execution unit.
// ============================================================================

package alu_pkg;

    typedef enum logic [3:0] {
        ALU_ADD   = 4'd0,
        ALU_SUB   = 4'd1,
        ALU_AND   = 4'd2,
        ALU_OR    = 4'd3,
        ALU_XOR   = 4'd4,
        ALU_SLL   = 4'd5,
        ALU_SRL   = 4'd6,
        ALU_SRA   = 4'd7,
        ALU_SLT   = 4'd8,
        ALU_SLTU  = 4'd9,
        ALU_PASS_B = 4'd10   // Pass operand B through (used for LUI)
    } alu_op_t;

endpackage

module alu
    import alu_pkg::*;
(
    input  logic [31:0] a,          // Operand A (typically rs1 or PC)
    input  logic [31:0] b,          // Operand B (typically rs2 or immediate)
    input  alu_op_t     op,         // Operation select
    output logic [31:0] result,     // ALU result
    output logic        zero        // Result is zero flag
);

    always_comb begin
        case (op)
            ALU_ADD:    result = a + b;
            ALU_SUB:    result = a - b;
            ALU_AND:    result = a & b;
            ALU_OR:     result = a | b;
            ALU_XOR:    result = a ^ b;
            ALU_SLL:    result = a << b[4:0];
            ALU_SRL:    result = a >> b[4:0];
            ALU_SRA:    result = $signed(a) >>> b[4:0];
            ALU_SLT:    result = {31'b0, $signed(a) < $signed(b)};
            ALU_SLTU:   result = {31'b0, a < b};
            ALU_PASS_B: result = b;
            default:    result = 32'b0;
        endcase
    end

    assign zero = (result == 32'b0);

endmodule


