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
// Package dependencies:
//   - alu_pkg   (from alu.sv)     — provides alu_op_t
//   - decode_pkg (defined below)  — provides instr_type_t
//
// Per project convention:
//   - alu_pkg is the single source of truth for ALU operation encoding.
//   - decode_pkg is the single source of truth for instruction type encoding.
//   - Future modules must use `import decode_pkg::*;` to access instr_type_t.
//   - Neither package will be moved or renamed without explicit notice.
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
//
// Legality enforcement:
//   - R-type instructions require exact funct7 values per the RV32I spec.
//   - I-type shifts (SLLI, SRLI, SRAI) require exact funct7 values.
//   - JALR requires funct3 == 3'b000.
//   - ECALL matches exactly 32'h0000_0073.
//   Any encoding that does not match these rules is flagged ILLEGAL.
//
// BRANCH RESOLUTION RULE (STABLE — do not change without notice):
//   Branches do NOT use the ALU.  The execution unit resolves all six
//   branch types using dedicated signed/unsigned comparison logic on
//   the raw rs1 and rs2 values, guided by funct3.  The decode unit
//   sets alu_op = ALU_ADD for branches as a don't-care default.
// ============================================================================

// ============================================================================
// decode_pkg — Instruction type enumeration
// ============================================================================
// Used by: reservation_station, reorder_buffer, execution_unit, ooo_cpu_core
// ============================================================================
package decode_pkg;

    typedef enum logic [2:0] {
        ITYPE_ALU     = 3'd0,    // R-type or I-type ALU operation
        ITYPE_BRANCH  = 3'd1,    // Conditional branch (BEQ, BNE, ...)
        ITYPE_JUMP    = 3'd2,    // JAL or JALR
        ITYPE_LUI     = 3'd3,    // Load upper immediate
        ITYPE_AUIPC   = 3'd4,    // Add upper immediate to PC
        ITYPE_HALT    = 3'd5,    // ECALL — program termination
        ITYPE_ILLEGAL = 3'd6     // Unrecognized or zero instruction
    } instr_type_t;

endpackage

// ============================================================================
// Decoder module
// ============================================================================
module decode_unit
    import alu_pkg::*;
    import decode_pkg::*;
(
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
    // funct7 constants for legality checks
    // ================================================================
    localparam logic [6:0] F7_ZERO = 7'b0000000;
    localparam logic [6:0] F7_SUB  = 7'b0100000;    // SUB, SRA, SRAI

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
                // R-type ALU
                // Each funct3/funct7 combination is validated exactly
                // per the RV32I spec.  Any mismatch → ILLEGAL.
                // ------------------------------------------------
                OP_ALUR: begin
                    uses_rs1 = 1'b1;
                    uses_rs2 = 1'b1;
                    uses_rd  = 1'b1;
                    uses_imm = 1'b0;
                    case (funct3)
                        3'b000: begin
                            if (funct7 == F7_ZERO) begin
                                alu_op = ALU_ADD;       // ADD
                                instr_type = ITYPE_ALU; decode_valid = 1'b1;
                            end else if (funct7 == F7_SUB) begin
                                alu_op = ALU_SUB;       // SUB
                                instr_type = ITYPE_ALU; decode_valid = 1'b1;
                            end
                            // else: defaults (ILLEGAL) stand
                        end
                        3'b001: begin
                            if (funct7 == F7_ZERO) begin
                                alu_op = ALU_SLL;       // SLL
                                instr_type = ITYPE_ALU; decode_valid = 1'b1;
                            end
                        end
                        3'b010: begin
                            if (funct7 == F7_ZERO) begin
                                alu_op = ALU_SLT;       // SLT
                                instr_type = ITYPE_ALU; decode_valid = 1'b1;
                            end
                        end
                        3'b011: begin
                            if (funct7 == F7_ZERO) begin
                                alu_op = ALU_SLTU;      // SLTU
                                instr_type = ITYPE_ALU; decode_valid = 1'b1;
                            end
                        end
                        3'b100: begin
                            if (funct7 == F7_ZERO) begin
                                alu_op = ALU_XOR;       // XOR
                                instr_type = ITYPE_ALU; decode_valid = 1'b1;
                            end
                        end
                        3'b101: begin
                            if (funct7 == F7_ZERO) begin
                                alu_op = ALU_SRL;       // SRL
                                instr_type = ITYPE_ALU; decode_valid = 1'b1;
                            end else if (funct7 == F7_SUB) begin
                                alu_op = ALU_SRA;       // SRA
                                instr_type = ITYPE_ALU; decode_valid = 1'b1;
                            end
                        end
                        3'b110: begin
                            if (funct7 == F7_ZERO) begin
                                alu_op = ALU_OR;        // OR
                                instr_type = ITYPE_ALU; decode_valid = 1'b1;
                            end
                        end
                        3'b111: begin
                            if (funct7 == F7_ZERO) begin
                                alu_op = ALU_AND;       // AND
                                instr_type = ITYPE_ALU; decode_valid = 1'b1;
                            end
                        end
                        default: ;  // ILLEGAL defaults stand
                    endcase
                end

                // ------------------------------------------------
                // I-type ALU: ADDI, ANDI, ORI, XORI, SLTI, SLTIU,
                //             SLLI, SRLI, SRAI
                // Shift instructions require exact funct7 values.
                // Non-shift instructions ignore funct7.
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
                            if (funct7 == F7_ZERO) begin
                                alu_op = ALU_SLL;
                                imm    = {27'b0, instr[24:20]};  // shamt
                            end else begin
                                decode_valid = 1'b0;
                                instr_type   = ITYPE_ILLEGAL;
                            end
                        end
                        3'b101: begin               // SRLI / SRAI
                            if (funct7 == F7_ZERO) begin
                                alu_op = ALU_SRL;               // SRLI
                                imm    = {27'b0, instr[24:20]};
                            end else if (funct7 == F7_SUB) begin
                                alu_op = ALU_SRA;               // SRAI
                                imm    = {27'b0, instr[24:20]};
                            end else begin
                                decode_valid = 1'b0;
                                instr_type   = ITYPE_ILLEGAL;
                            end
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
                    alu_op       = ALU_ADD;       // Exec computes PC+4 for rd
                    is_jump      = 1'b1;
                    decode_valid = 1'b1;
                end

                // ------------------------------------------------
                // JALR: rd = PC+4, jump to (rs1 + imm_i) & ~1
                // Requires funct3 == 3'b000 per RV32I spec.
                // ------------------------------------------------
                OP_JALR: begin
                    if (funct3 == 3'b000) begin
                        instr_type   = ITYPE_JUMP;
                        uses_rs1     = 1'b1;
                        uses_rs2     = 1'b0;
                        uses_rd      = 1'b1;
                        uses_imm     = 1'b1;
                        imm          = imm_i;
                        alu_op       = ALU_ADD;   // Exec computes PC+4 for rd
                        is_jump      = 1'b1;
                        decode_valid = 1'b1;
                    end
                    // else: defaults (ILLEGAL) stand
                end

                // ------------------------------------------------
                // Branches: BEQ, BNE, BLT, BGE, BLTU, BGEU
                //
                // BRANCH RESOLUTION RULE:
                //   The ALU is NOT used for branches.  alu_op is set
                //   to ALU_ADD as a don't-care default.  The execution
                //   unit resolves branches using dedicated comparison
                //   logic on raw rs1/rs2 values, guided by funct3.
                // ------------------------------------------------
                OP_BRANCH: begin
                    // Validate funct3 first
                    case (funct3)
                        3'b000,  // BEQ
                        3'b001,  // BNE
                        3'b100,  // BLT
                        3'b101,  // BGE
                        3'b110,  // BLTU
                        3'b111: begin // BGEU
                            instr_type   = ITYPE_BRANCH;
                            uses_rs1     = 1'b1;
                            uses_rs2     = 1'b1;
                            uses_rd      = 1'b0;
                            uses_imm     = 1'b1;
                            imm          = imm_b;
                            alu_op       = ALU_ADD;    // Don't-care
                            is_branch    = 1'b1;
                            decode_valid = 1'b1;
                        end
                        default: ;  // ILLEGAL defaults stand
                    endcase
                end

                // ------------------------------------------------
                // ECALL — treated as HALT
                // Exact match: 32'h0000_0073
                // ------------------------------------------------
                OP_SYSTEM: begin
                    if (instr == 32'h0000_0073) begin
                        instr_type   = ITYPE_HALT;
                        uses_rd      = 1'b0;
                        decode_valid = 1'b1;
                    end
                    // else: defaults (ILLEGAL) stand
                end

                // ------------------------------------------------
                // LOAD / STORE — not yet supported
                // ------------------------------------------------
                OP_LOAD, OP_STORE: ;  // ILLEGAL defaults stand

                // ------------------------------------------------
                // Everything else: illegal
                // ------------------------------------------------
                default: ;  // ILLEGAL defaults stand
            endcase
        end
    end

endmodule
