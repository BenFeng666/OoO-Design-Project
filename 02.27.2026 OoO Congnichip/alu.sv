// ALU Module for RV32I Out-of-Order CPU Core
// Supports all integer arithmetic, logical, and shift operations

module alu (
    input  logic [31:0] operand_a,      // First operand
    input  logic [31:0] operand_b,      // Second operand
    input  logic [3:0]  alu_op,         // ALU operation select
    output logic [31:0] result          // ALU result
);

    // ALU operation encodings
    typedef enum logic [3:0] {
        ALU_ADD  = 4'b0000,  // Addition
        ALU_SUB  = 4'b0001,  // Subtraction
        ALU_SLL  = 4'b0010,  // Shift left logical
        ALU_SLT  = 4'b0011,  // Set less than (signed)
        ALU_SLTU = 4'b0100,  // Set less than unsigned
        ALU_XOR  = 4'b0101,  // Bitwise XOR
        ALU_SRL  = 4'b0110,  // Shift right logical
        ALU_SRA  = 4'b0111,  // Shift right arithmetic
        ALU_OR   = 4'b1000,  // Bitwise OR
        ALU_AND  = 4'b1001   // Bitwise AND
    } alu_op_e;

    // Shift amount (lower 5 bits of operand_b for RV32I)
    logic [4:0] shamt;
    assign shamt = operand_b[4:0];

    // Combinational ALU logic
    always_comb begin
        result = 32'b0;
        
        case (alu_op)
            ALU_ADD:  result = operand_a + operand_b;
            ALU_SUB:  result = operand_a - operand_b;
            ALU_SLL:  result = operand_a << shamt;
            ALU_SLT:  result = {31'b0, $signed(operand_a) < $signed(operand_b)};
            ALU_SLTU: result = {31'b0, operand_a < operand_b};
            ALU_XOR:  result = operand_a ^ operand_b;
            ALU_SRL:  result = operand_a >> shamt;
            ALU_SRA:  result = $signed(operand_a) >>> shamt;
            ALU_OR:   result = operand_a | operand_b;
            ALU_AND:  result = operand_a & operand_b;
            default:  result = 32'b0;
        endcase
    end

endmodule