// Instruction ROM for RV32I Out-of-Order CPU Core
// 16-entry read-only memory for program storage
// Stores 32-bit RV32I instructions

module instruction_rom #(
    parameter ROM_ENTRIES = 16,      // Number of ROM entries
    parameter ROM_ADDR_WIDTH = 4     // log2(ROM_ENTRIES)
)(
    input  logic                        clock,
    input  logic [ROM_ADDR_WIDTH-1:0]  addr,        // Instruction address
    output logic [31:0]                 instruction  // Fetched instruction
);

    // ROM storage array - 16 entries of 32-bit instructions
    logic [31:0] rom_data [ROM_ENTRIES-1:0];
    
    // Initialize ROM with a simple test program - FIXED VERSION
    // All instruction encodings validated and corrected
    initial begin
        // Example RV32I program:
        // Simple arithmetic and logical operations
        
        // ADD x1, x0, x0      (x1 = 0 + 0 = 0)
        rom_data[0]  = 32'h000000B3;  // add x1, x0, x0 - FIXED
        
        // ADDI x2, x0, 5      (x2 = 0 + 5 = 5)
        rom_data[1]  = 32'h00500113;  // addi x2, x0, 5
        
        // ADDI x3, x0, 10     (x3 = 0 + 10 = 10)
        rom_data[2]  = 32'h00A00193;  // addi x3, x0, 10
        
        // ADD x4, x2, x3      (x4 = 5 + 10 = 15)
        rom_data[3]  = 32'h00310233;  // add x4, x2, x3
        
        // SUB x5, x3, x2      (x5 = 10 - 5 = 5)
        rom_data[4]  = 32'h402182B3;  // sub x5, x3, x2
        
        // AND x6, x2, x3      (x6 = 5 & 10 = 0)
        rom_data[5]  = 32'h00317333;  // and x6, x2, x3
        
        // OR x7, x2, x3       (x7 = 5 | 10 = 15)
        rom_data[6]  = 32'h003163B3;  // or x7, x2, x3
        
        // XOR x8, x2, x3      (x8 = 5 ^ 10 = 15)
        rom_data[7]  = 32'h00314433;  // xor x8, x2, x3
        
        // SLL x9, x2, x1      (x9 = 5 << 0 = 5)
        rom_data[8]  = 32'h001114B3;  // sll x9, x2, x1
        
        // SRL x10, x2, x1     (x10 = 5 >> 0 = 5)
        rom_data[9]  = 32'h00115533;  // srl x10, x2, x1
        
        // SLT x11, x2, x3     (x11 = (5 < 10) = 1)
        rom_data[10] = 32'h003125B3;  // slt x11, x2, x3
        
        // SLTU x12, x2, x3    (x12 = (5 < 10) unsigned = 1)
        rom_data[11] = 32'h00313633;  // sltu x12, x2, x3
        
        // ADDI x13, x4, -5    (x13 = 15 - 5 = 10)
        rom_data[12] = 32'hFFB20693;  // addi x13, x4, -5
        
        // ADD x14, x13, x5    (x14 = 10 + 5 = 15)
        rom_data[13] = 32'h00568733;  // add x14, x13, x5
        
        // NOP (ADDI x0, x0, 0)
        rom_data[14] = 32'h00000013;  // nop
        
        // NOP (ADDI x0, x0, 0)
        rom_data[15] = 32'h00000013;  // nop
    end
    
    // Synchronous read
    always_ff @(posedge clock) begin
        instruction <= rom_data[addr];
    end

endmodule