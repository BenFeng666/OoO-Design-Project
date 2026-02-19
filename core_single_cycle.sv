// Single-Cycle RV32I Core - Top Level Integration
// Connects all datapath and control components

module core_single_cycle #(
    parameter RESET_ADDR = 32'h00000000
) (
    input  logic        clock,
    input  logic        reset,
    
    // Instruction Memory Interface
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_data,
    
    // Data Memory Interface
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_write_data,
    output logic [3:0]  dmem_byte_enable,
    output logic        dmem_read,
    output logic        dmem_write,
    input  logic [31:0] dmem_read_data
);

    // ========== Internal Signals ==========
    
    // PC signals
    logic [31:0] pc_current, pc_next, pc_plus_4;
    
    // Instruction decode
    logic [31:0] instruction;
    logic [4:0]  rs1, rs2, rd;
    
    // Control signals
    logic [3:0]  alu_control;
    logic [2:0]  imm_type;
    logic        reg_write;
    logic        mem_read;
    logic        mem_write;
    logic        alu_src;
    logic [1:0]  wb_src;
    logic        branch;
    logic        jump;
    logic [2:0]  funct3;
    
    // Register file signals
    logic [31:0] reg_read_data1, reg_read_data2;
    logic [31:0] reg_write_data;
    
    // Immediate generator
    logic [31:0] immediate;
    
    // ALU signals
    logic [31:0] alu_operand_a, alu_operand_b;
    logic [31:0] alu_result;
    logic        alu_zero;
    
    // Memory alignment signals
    logic [31:0] load_data_aligned;
    logic [31:0] store_data_aligned;
    
    // Branch logic signals
    logic        branch_taken;
    logic [31:0] branch_target;
    logic [31:0] jump_target;
    
    // ========== Instruction Fetch ==========
    
    // PC calculation
    assign pc_plus_4 = pc_current + 32'd4;
    
    // Branch target address
    assign branch_target = pc_current + immediate;
    
    // Jump target addresses
    assign jump_target = (funct3 == 3'b000 && jump) ? (alu_result & 32'hFFFFFFFE) : // JALR (mask LSB)
                                                        (pc_current + immediate);      // JAL
    
    // PC next logic
    always_comb begin
        if (jump) begin
            pc_next = jump_target;
        end else if (branch && branch_taken) begin
            pc_next = branch_target;
        end else begin
            pc_next = pc_plus_4;
        end
    end
    
    // Instruction memory address
    assign imem_addr = pc_current;
    assign instruction = imem_data;
    
    // ========== Instruction Decode ==========
    
    // Extract register addresses
    assign rs1 = instruction[19:15];
    assign rs2 = instruction[24:20];
    assign rd  = instruction[11:7];
    
    // ========== Execute Stage ==========
    
    // ALU operand A (always from rs1, except for AUIPC where it's PC)
    assign alu_operand_a = (instruction[6:0] == 7'b0010111) ? pc_current : reg_read_data1; // AUIPC uses PC
    
    // ALU operand B (register or immediate)
    assign alu_operand_b = alu_src ? immediate : reg_read_data2;
    
    // ========== Branch Decision Logic ==========
    
    // Branch conditions based on funct3
    always_comb begin
        case (funct3)
            3'b000: branch_taken = (reg_read_data1 == reg_read_data2);                    // BEQ
            3'b001: branch_taken = (reg_read_data1 != reg_read_data2);                    // BNE
            3'b100: branch_taken = ($signed(reg_read_data1) < $signed(reg_read_data2));   // BLT
            3'b101: branch_taken = ($signed(reg_read_data1) >= $signed(reg_read_data2));  // BGE
            3'b110: branch_taken = (reg_read_data1 < reg_read_data2);                     // BLTU
            3'b111: branch_taken = (reg_read_data1 >= reg_read_data2);                    // BGEU
            default: branch_taken = 1'b0;
        endcase
    end
    
    // ========== Memory Stage ==========
    
    // Data memory connections
    assign dmem_addr = alu_result;
    assign dmem_read = mem_read;
    assign dmem_write = mem_write;
    assign dmem_write_data = store_data_aligned;
    
    // ========== Write Back Stage ==========
    
    // Write-back data multiplexer
    always_comb begin
        case (wb_src)
            2'b00: reg_write_data = alu_result;      // ALU result
            2'b01: reg_write_data = load_data_aligned; // Memory load
            2'b10: reg_write_data = pc_plus_4;       // PC+4 (for JAL/JALR)
            default: reg_write_data = alu_result;
        endcase
    end
    
    // Special handling for LUI - load immediate directly
    assign reg_write_data = (instruction[6:0] == 7'b0110111) ? immediate : reg_write_data;
    
    // ========== Module Instantiations ==========
    
    // Program Counter
    pc #(
        .RESET_ADDR(RESET_ADDR)
    ) u_pc (
        .clock(clock),
        .reset(reset),
        .pc_next(pc_next),
        .pc_current(pc_current)
    );
    
    // Control Unit
    control_unit u_control_unit (
        .instruction(instruction),
        .alu_control(alu_control),
        .imm_type(imm_type),
        .reg_write(reg_write),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .alu_src(alu_src),
        .wb_src(wb_src),
        .branch(branch),
        .jump(jump),
        .funct3(funct3)
    );
    
    // Register File
    register_file u_register_file (
        .clock(clock),
        .reset(reset),
        .read_addr1(rs1),
        .read_data1(reg_read_data1),
        .read_addr2(rs2),
        .read_data2(reg_read_data2),
        .write_addr(rd),
        .write_data(reg_write_data),
        .write_enable(reg_write)
    );
    
    // Immediate Generator
    immediate_generator u_immediate_generator (
        .instruction(instruction),
        .imm_type(imm_type),
        .immediate(immediate)
    );
    
    // ALU
    alu u_alu (
        .operand_a(alu_operand_a),
        .operand_b(alu_operand_b),
        .alu_control(alu_control),
        .result(alu_result),
        .zero(alu_zero)
    );
    
    // Load/Store Alignment
    load_store_align u_load_store_align (
        .address_offset(alu_result[1:0]),
        .funct3(funct3),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .mem_read_data(dmem_read_data),
        .load_data_aligned(load_data_aligned),
        .store_data(reg_read_data2),
        .store_data_aligned(store_data_aligned),
        .byte_enable(dmem_byte_enable)
    );

endmodule