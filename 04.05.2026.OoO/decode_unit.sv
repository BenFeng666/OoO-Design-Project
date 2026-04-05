// ============================================================================
// decode_unit.sv — RV32I Instruction Decoder
// ============================================================================
// Combinational decoder: cracks a 32-bit RV32I instruction into all fields
// needed by downstream dispatch logic (reservation station + ROB allocation).
//
// This module does NOT perform dispatch.  It only extracts and classifies.
// The top-level core coordinates register reads, ROB allocation, and RS
// issue using the decoded bundle this module produces.
//
// Uses alu_pkg (defined in alu.sv) for alu_op_t.  Per project convention,
// alu_pkg is the single source of truth for ALU operation encoding.
//
// Supported RV32I subset:
//   R-type:  ADD SUB AND OR XOR SLL SRL SRA SLT SLTU
//   I-type:  ADDI ANDI ORI XORI SLLI SRLI SRAI SLTI SLTIU
//   Upper:   LUI AUIPC
//   Jump:    JAL JALR
//   Branch:  BEQ BNE BLT BGE BLTU BGEU
//   System:  ECALL (treated as HALT)
//
// NOT supported yet: LOAD, STORE, FENCE, EBREAK.
// 32'h0 is treated as ILLEGAL (not NOP).
// ============================================================================

import alu_pkg::*;

// ============================================================================
// Instruction type enum — used by RS, ROB, and execution to decide behavior
// ============================================================================
typedef enum logic [2:0] {
    ITYPE_ALU     = 3'd0,    // R-type or I-type ALU operation
    ITYPE_BRANCH  = 3'd1,    // Conditional branch (BEQ, BNE, ...)
    ITYPE_JUMP    = 3'd2,    // JAL or JALR
    ITYPE_LUI     = 3'd3,    // Load upper immediate
    ITYPE_AUIPC   = 3'd4,    // Add upper immediate to PC
    ITYPE_HALT    = 3'd5,    // ECALL — program termination
    ITYPE_ILLEGAL = 3'd6     // Unrecognized or zero instruction
} instr_type_t;

module decode_unit (
    // --- Input: fetched instruction ---
    input  logic [31:0]  instr,          // Raw 32-bit instruction word
    input  logic [31:0]  pc,             // PC of this instruction
    input  logic         instr_valid,    // Fetch says this is a real instruction

    // --- Output: decoded bundle ---
    output logic [4:0]   rs1_addr,       // Source register 1 address
    output logic [4:0]   rs2_addr,       // Source register 2 address
    output logic [4:0]   rd_addr,        // Destination register address
    output logic         uses_rs1,       // Instruction reads rs1
    output logic         uses_rs2,       // Instruction reads rs2
    output logic         uses_rd,        // Instruction writes rd
    output logic [31:0]  imm,            // Sign-extended immediate
    output logic         uses_imm,       // Operand B is immediate (not rs2)
    output alu_op_t      alu_op,         // ALU operation select
    output instr_type_t  instr_type,     // Instruction category
    output logic         is_branch,      // Conditional branch
    output logic         is_jump,        // JAL or JALR
    output logic [2:0]   funct3_out,     // funct3 passthrough (for branch type)
    output logic [31:0]  pc_out,         // PC passthrough (for AUIPC, JAL, branches)
    output logic         decode_valid    // Instruction successfully decoded
);

    // ================================================================
    // Field extraction
    // ================================================================
    logic [6:0]  opcode;
    logic [4:0]  rd_raw, rs1_raw, rs2_raw;
    logic [2:0]  funct3;
    logic [6:0]  funct7;

    assign opcode  = instr[6:0];
    assign rd_raw  = instr[11:7];
    assign funct3  = instr[14:12];
    assign rs1_raw = instr[19:15];
    assign rs2_raw = instr[24:20];
    assign funct7  = instr[31:25];

    // ================================================================
    // Immediate generation
    // ================================================================
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;

    // I-type: sign-extend instr[31:20]
    assign imm_i = {{20{instr[31]}}, instr[31:20]};

    // S-type: sign-extend {instr[31:25], instr[11:7]}
    assign imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};

    // B-type: sign-extend {instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}
    assign imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};

    // U-type: {instr[31:12], 12'b0}
    assign imm_u = {instr[31:12], 12'b0};

    // J-type: sign-extend {instr[31], instr[19:12], instr[20], instr[30:21], 1'b0}
    assign imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    // ================================================================
    // RV32I opcode constants
    // ================================================================
    localparam logic [6:0] OP_LUI    = 7'b0110111;
    localparam logic [6:0] OP_AUIPC  = 7'b0010111;
    localparam logic [6:0] OP_JAL    = 7'b1101111;
    localparam logic [6:0] OP_JALR   = 7'b1100111;
    localparam logic [6:0] OP_BRANCH = 7'b1100011;
    localparam logic [6:0] OP_LOAD   = 7'b0000011;
    localparam logic [6:0] OP_STORE  = 7'b0100011;
    localparam logic [6:0] OP_ALUI   = 7'b0010011;  // I-type ALU
    localparam logic [6:0] OP_ALUR   = 7'b0110011;  // R-type ALU
    localparam logic [6:0] OP_SYSTEM = 7'b1110011;

    // ================================================================
    // Main decode logic
    // ================================================================
    always_comb begin
        // ----- Defaults (ILLEGAL) -----
        rs1_addr     = 5'b0;
        rs2_addr     = 5'b0;
        rd_addr      = 5'b0;
        uses_rs1     = 1'b0;
        uses_rs2     = 1'b0;
        uses_rd      = 1'b0;
        imm          = 32'b0;
        uses_imm     = 1'b0;
        alu_op       = ALU_ADD;
        instr_type   = ITYPE_ILLEGAL;
        is_branch    = 1'b0;
        is_jump      = 1'b0;
        funct3_out   = 3'b0;
        pc_out       = pc;
        decode_valid = 1'b0;

        if (instr_valid && (instr != 32'b0)) begin
            // Common field assignments (overridden per opcode as needed)
            rs1_addr   = rs1_raw;
            rs2_addr   = rs2_raw;
            rd_addr    = rd_raw;
            funct3_out = funct3;

            case (opcode)
                // ------------------------------------------------
                // R-type ALU: ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU
                // ------------------------------------------------
                OP_ALUR: begin
                    instr_type   = ITYPE_ALU;
                    uses_rs1     = 1'b1;
                    uses_rs2     = 1'b1;
                    uses_rd      = 1'b1;
                    uses_imm     = 1'b0;
                    decode_valid = 1'b1;
                    case (funct3)
                        3'b000: alu_op = (funct7[5]) ? ALU_SUB : ALU_ADD;
                        3'b001: alu_op = ALU_SLL;
                        3'b010: alu_op = ALU_SLT;
                        3'b011: alu_op = ALU_SLTU;
                        3'b100: alu_op = ALU_XOR;
                        3'b101: alu_op = (funct7[5]) ? ALU_SRA : ALU_SRL;
                        3'b110: alu_op = ALU_OR;
                        3'b111: alu_op = ALU_AND;
                        default: begin
                            decode_valid = 1'b0;
                            instr_type   = ITYPE_ILLEGAL;
                        end
                    endcase
                end

                // ------------------------------------------------
                // I-type ALU: ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI
                // ------------------------------------------------
                OP_ALUI: begin
                    instr_type   = ITYPE_ALU;
                    uses_rs1     = 1'b1;
                    uses_rs2     = 1'b0;
                    uses_rd      = 1'b1;
                    uses_imm     = 1'b1;
                    imm          = imm_i;
                    decode_valid = 1'b1;
                    case (funct3)
                        3'b000: alu_op = ALU_ADD;   // ADDI
                        3'b010: alu_op = ALU_SLT;   // SLTI
                        3'b011: alu_op = ALU_SLTU;  // SLTIU
                        3'b100: alu_op = ALU_XOR;   // XORI
                        3'b110: alu_op = ALU_OR;    // ORI
                        3'b111: alu_op = ALU_AND;   // ANDI
                        3'b001: begin               // SLLI
                            alu_op = ALU_SLL;
                            imm    = {27'b0, instr[24:20]};  // shamt
                        end
                        3'b101: begin               // SRLI / SRAI
                            alu_op = (funct7[5]) ? ALU_SRA : ALU_SRL;
                            imm    = {27'b0, instr[24:20]};  // shamt
                        end
                        default: begin
                            decode_valid = 1'b0;
                            instr_type   = ITYPE_ILLEGAL;
                        end
                    endcase
                end

                // ------------------------------------------------
                // LUI: rd = imm_u
                // ------------------------------------------------
                OP_LUI: begin
                    instr_type   = ITYPE_LUI;
                    uses_rs1     = 1'b0;
                    uses_rs2     = 1'b0;
                    uses_rd      = 1'b1;
                    uses_imm     = 1'b1;
                    imm          = imm_u;
                    alu_op       = ALU_PASS_B;   // Result = immediate
                    decode_valid = 1'b1;
                end

                // ------------------------------------------------
                // AUIPC: rd = PC + imm_u
                // ------------------------------------------------
                OP_AUIPC: begin
                    instr_type   = ITYPE_AUIPC;
                    uses_rs1     = 1'b0;
                    uses_rs2     = 1'b0;
                    uses_rd      = 1'b1;
                    uses_imm     = 1'b1;
                    imm          = imm_u;
                    alu_op       = ALU_ADD;       // Result = PC + imm_u
                    decode_valid = 1'b1;
                end

                // ------------------------------------------------
                // JAL: rd = PC+4, jump to PC + imm_j
                // ------------------------------------------------
                OP_JAL: begin
                    instr_type   = ITYPE_JUMP;
                    uses_rs1     = 1'b0;
                    uses_rs2     = 1'b0;
                    uses_rd      = 1'b1;
                    uses_imm     = 1'b1;
                    imm          = imm_j;
                    alu_op       = ALU_ADD;       // Execution computes PC + 4 for link
                    is_jump      = 1'b1;
                    decode_valid = 1'b1;
                end

                // ------------------------------------------------
                // JALR: rd = PC+4, jump to (rs1 + imm_i) & ~1
                // ------------------------------------------------
                OP_JALR: begin
                    instr_type   = ITYPE_JUMP;
                    uses_rs1     = 1'b1;
                    uses_rs2     = 1'b0;
                    uses_rd      = 1'b1;
                    uses_imm     = 1'b1;
                    imm          = imm_i;
                    alu_op       = ALU_ADD;       // Execution computes PC + 4 for link
                    is_jump      = 1'b1;
                    decode_valid = 1'b1;
                end

                // ------------------------------------------------
                // Branches: BEQ, BNE, BLT, BGE, BLTU, BGEU
                // ------------------------------------------------
                OP_BRANCH: begin
                    instr_type   = ITYPE_BRANCH;
                    uses_rs1     = 1'b1;
                    uses_rs2     = 1'b1;
                    uses_rd      = 1'b0;           // Branches don't write rd
                    uses_imm     = 1'b1;
                    imm          = imm_b;
                    alu_op       = ALU_SUB;        // Compare rs1 - rs2
                    is_branch    = 1'b1;
                    decode_valid = 1'b1;

                    // Validate funct3 for known branch types
                    case (funct3)
                        3'b000,  // BEQ
                        3'b001,  // BNE
                        3'b100,  // BLT
                        3'b101,  // BGE
                        3'b110,  // BLTU
                        3'b111:  // BGEU
                            ;    // Valid
                        default: begin
                            decode_valid = 1'b0;
                            instr_type   = ITYPE_ILLEGAL;
                        end
                    endcase
                end

                // ------------------------------------------------
                // ECALL — treated as HALT
                // ------------------------------------------------
                OP_SYSTEM: begin
                    if (instr[31:7] == 25'b0) begin
                        // ECALL encoding: all upper bits zero
                        instr_type   = ITYPE_HALT;
                        uses_rd      = 1'b0;
                        decode_valid = 1'b1;
                    end else begin
                        instr_type   = ITYPE_ILLEGAL;
                        decode_valid = 1'b0;
                    end
                end

                // ------------------------------------------------
                // LOAD / STORE — not yet supported, decode as illegal
                // ------------------------------------------------
                OP_LOAD, OP_STORE: begin
                    instr_type   = ITYPE_ILLEGAL;
                    decode_valid = 1'b0;
                end

                // ------------------------------------------------
                // Everything else: illegal
                // ------------------------------------------------
                default: begin
                    instr_type   = ITYPE_ILLEGAL;
                    decode_valid = 1'b0;
                end
            endcase
        end
    end

endmodule
