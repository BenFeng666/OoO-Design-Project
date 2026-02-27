// Decode Unit for RV32I Out-of-Order CPU Core
// Decodes RV32I instructions and prepares for dispatch
// Handles register renaming and operand preparation

module decode_unit #(
    parameter ROB_ADDR_WIDTH = 4      // ROB tag width
)(
    input  logic                        clock,
    input  logic                        reset,
    
    // Input instruction from fetch
    input  logic [31:0]                 instruction,        // Instruction to decode
    input  logic                        instruction_valid,  // Instruction is valid
    
    // Register file read ports
    output logic [4:0]                  rs1_addr,           // Source register 1 address
    input  logic [31:0]                 rs1_value,          // Source register 1 value
    input  logic                        rs1_valid,          // rs1 value is ready
    input  logic [ROB_ADDR_WIDTH-1:0]   rs1_tag,            // rs1 ROB tag if not ready
    
    output logic [4:0]                  rs2_addr,           // Source register 2 address
    input  logic [31:0]                 rs2_value,          // Source register 2 value
    input  logic                        rs2_valid,          // rs2 value is ready
    input  logic [ROB_ADDR_WIDTH-1:0]   rs2_tag,            // rs2 ROB tag if not ready
    
    // ROB allocation
    input  logic [ROB_ADDR_WIDTH-1:0]   rob_tag,            // Allocated ROB tag
    input  logic                        rob_full,           // ROB is full
    
    // Reservation Station dispatch
    output logic                        dispatch_valid,     // Dispatch to RS
    output logic [3:0]                  dispatch_alu_op,    // ALU operation
    output logic [31:0]                 dispatch_src1_value,// Source 1 value
    output logic                        dispatch_src1_ready,// Source 1 ready
    output logic [ROB_ADDR_WIDTH-1:0]   dispatch_src1_tag,  // Source 1 tag
    output logic [31:0]                 dispatch_src2_value,// Source 2 value
    output logic                        dispatch_src2_ready,// Source 2 ready
    output logic [ROB_ADDR_WIDTH-1:0]   dispatch_src2_tag,  // Source 2 tag
    output logic [ROB_ADDR_WIDTH-1:0]   dispatch_dest_tag,  // Destination tag
    input  logic                        rs_full,            // RS is full
    
    // ROB allocation interface
    output logic                        rob_alloc_valid,    // Allocate ROB entry
    output logic [4:0]                  rob_dest_reg,       // Destination register
    output logic                        rob_dest_valid,     // Has destination register
    
    // Register renaming interface
    output logic                        rename_valid,       // Rename destination
    output logic [4:0]                  rename_dest_reg,    // Destination to rename
    output logic [ROB_ADDR_WIDTH-1:0]   rename_rob_tag      // ROB tag for renaming
);

    // RV32I instruction fields
    logic [6:0]  opcode;
    logic [4:0]  rd;
    logic [2:0]  funct3;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [6:0]  funct7;
    logic [31:0] imm_i;      // I-type immediate
    
    // Decoded signals
    logic        is_r_type;  // R-type (register-register)
    logic        is_i_type;  // I-type (immediate)
    logic        use_imm;    // Use immediate instead of rs2
    logic        valid_instr;// Valid instruction
    
    // Extract instruction fields
    assign opcode = instruction[6:0];
    assign rd     = instruction[11:7];
    assign funct3 = instruction[14:12];
    assign rs1    = instruction[19:15];
    assign rs2    = instruction[24:20];
    assign funct7 = instruction[31:25];
    
    // Sign-extend I-type immediate
    assign imm_i = {{20{instruction[31]}}, instruction[31:20]};
    
    // Decode instruction type
    always_comb begin
        is_r_type   = (opcode == 7'b0110011);  // R-type ALU ops
        is_i_type   = (opcode == 7'b0010011);  // I-type ALU ops
        use_imm     = is_i_type;
        valid_instr = is_r_type || is_i_type;
    end
    
    // Generate ALU operation code
    logic [3:0] alu_op;
    always_comb begin
        alu_op = 4'b0000;  // Default to ADD
        
        case (funct3)
            3'b000: begin  // ADD/SUB or ADDI
                if (is_r_type && funct7[5])
                    alu_op = 4'b0001;  // SUB
                else
                    alu_op = 4'b0000;  // ADD/ADDI
            end
            3'b001: alu_op = 4'b0010;  // SLL/SLLI
            3'b010: alu_op = 4'b0011;  // SLT/SLTI
            3'b011: alu_op = 4'b0100;  // SLTU/SLTIU
            3'b100: alu_op = 4'b0101;  // XOR/XORI
            3'b101: begin  // SRL/SRA or SRLI/SRAI
                if (funct7[5])
                    alu_op = 4'b0111;  // SRA/SRAI
                else
                    alu_op = 4'b0110;  // SRL/SRLI
            end
            3'b110: alu_op = 4'b1000;  // OR/ORI
            3'b111: alu_op = 4'b1001;  // AND/ANDI
        endcase
    end
    
    // Register file read addresses
    assign rs1_addr = rs1;
    assign rs2_addr = rs2;
    
    // Prepare source operand 1
    logic [31:0] src1_value;
    logic        src1_ready;
    logic [ROB_ADDR_WIDTH-1:0] src1_tag;
    
    assign src1_value = rs1_value;
    assign src1_ready = rs1_valid;
    assign src1_tag   = rs1_tag;
    
    // Prepare source operand 2 (register or immediate)
    logic [31:0] src2_value;
    logic        src2_ready;
    logic [ROB_ADDR_WIDTH-1:0] src2_tag;
    
    always_comb begin
        if (use_imm) begin
            // I-type: use immediate value
            src2_value = imm_i;
            src2_ready = 1'b1;
            src2_tag   = '0;
        end else begin
            // R-type: use register value
            src2_value = rs2_value;
            src2_ready = rs2_valid;
            src2_tag   = rs2_tag;
        end
    end
    
    // Dispatch logic
    logic can_dispatch;
    assign can_dispatch = instruction_valid && valid_instr && !rob_full && !rs_full;
    
    assign dispatch_valid     = can_dispatch;
    assign dispatch_alu_op    = alu_op;
    assign dispatch_src1_value = src1_value;
    assign dispatch_src1_ready = src1_ready;
    assign dispatch_src1_tag  = src1_tag;
    assign dispatch_src2_value = src2_value;
    assign dispatch_src2_ready = src2_ready;
    assign dispatch_src2_tag  = src2_tag;
    assign dispatch_dest_tag  = rob_tag;
    
    // ROB allocation
    assign rob_alloc_valid = can_dispatch;
    assign rob_dest_reg    = rd;
    assign rob_dest_valid  = (rd != 5'b0);  // Only valid if not x0
    
    // Register renaming
    assign rename_valid    = can_dispatch && (rd != 5'b0);
    assign rename_dest_reg = rd;
    assign rename_rob_tag  = rob_tag;

endmodule