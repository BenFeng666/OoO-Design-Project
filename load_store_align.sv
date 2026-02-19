// Load/Store Alignment Logic for RV32I Single-Cycle Core
// Handles byte/halfword/word loads and stores with proper alignment

module load_store_align (
    input  logic [1:0]  address_offset,  // Address[1:0] for alignment
    input  logic [2:0]  funct3,          // Load/store type from instruction
    input  logic        mem_read,        // Load operation flag
    input  logic        mem_write,       // Store operation flag
    
    // Load path
    input  logic [31:0] mem_read_data,   // 32-bit data from memory
    output logic [31:0] load_data_aligned, // Aligned and extended data to register
    
    // Store path
    input  logic [31:0] store_data,      // 32-bit data from register
    output logic [31:0] store_data_aligned, // Aligned data to memory
    output logic [3:0]  byte_enable      // Byte enable for memory write
);

    // Load/Store funct3 encoding
    localparam FUNCT3_BYTE      = 3'b000;  // LB/SB
    localparam FUNCT3_HALF      = 3'b001;  // LH/SH
    localparam FUNCT3_WORD      = 3'b010;  // LW/SW
    localparam FUNCT3_BYTE_U    = 3'b100;  // LBU
    localparam FUNCT3_HALF_U    = 3'b101;  // LHU
    
    // Load alignment and extension logic
    always_comb begin
        if (mem_read) begin
            case (funct3)
                FUNCT3_BYTE: begin
                    // LB - Load Byte (sign-extended)
                    case (address_offset)
                        2'b00: load_data_aligned = {{24{mem_read_data[7]}},  mem_read_data[7:0]};
                        2'b01: load_data_aligned = {{24{mem_read_data[15]}}, mem_read_data[15:8]};
                        2'b10: load_data_aligned = {{24{mem_read_data[23]}}, mem_read_data[23:16]};
                        2'b11: load_data_aligned = {{24{mem_read_data[31]}}, mem_read_data[31:24]};
                    endcase
                end
                
                FUNCT3_BYTE_U: begin
                    // LBU - Load Byte Unsigned (zero-extended)
                    case (address_offset)
                        2'b00: load_data_aligned = {24'h000000, mem_read_data[7:0]};
                        2'b01: load_data_aligned = {24'h000000, mem_read_data[15:8]};
                        2'b10: load_data_aligned = {24'h000000, mem_read_data[23:16]};
                        2'b11: load_data_aligned = {24'h000000, mem_read_data[31:24]};
                    endcase
                end
                
                FUNCT3_HALF: begin
                    // LH - Load Halfword (sign-extended)
                    case (address_offset[1])
                        1'b0: load_data_aligned = {{16{mem_read_data[15]}}, mem_read_data[15:0]};
                        1'b1: load_data_aligned = {{16{mem_read_data[31]}}, mem_read_data[31:16]};
                    endcase
                end
                
                FUNCT3_HALF_U: begin
                    // LHU - Load Halfword Unsigned (zero-extended)
                    case (address_offset[1])
                        1'b0: load_data_aligned = {16'h0000, mem_read_data[15:0]};
                        1'b1: load_data_aligned = {16'h0000, mem_read_data[31:16]};
                    endcase
                end
                
                FUNCT3_WORD: begin
                    // LW - Load Word (no alignment needed)
                    load_data_aligned = mem_read_data;
                end
                
                default: begin
                    load_data_aligned = 32'h00000000;
                end
            endcase
        end else begin
            load_data_aligned = 32'h00000000;
        end
    end
    
    // Store alignment and byte enable logic
    always_comb begin
        if (mem_write) begin
            case (funct3)
                FUNCT3_BYTE: begin
                    // SB - Store Byte
                    case (address_offset)
                        2'b00: begin
                            store_data_aligned = {24'h000000, store_data[7:0]};
                            byte_enable = 4'b0001;
                        end
                        2'b01: begin
                            store_data_aligned = {16'h0000, store_data[7:0], 8'h00};
                            byte_enable = 4'b0010;
                        end
                        2'b10: begin
                            store_data_aligned = {8'h00, store_data[7:0], 16'h0000};
                            byte_enable = 4'b0100;
                        end
                        2'b11: begin
                            store_data_aligned = {store_data[7:0], 24'h000000};
                            byte_enable = 4'b1000;
                        end
                    endcase
                end
                
                FUNCT3_HALF: begin
                    // SH - Store Halfword
                    case (address_offset[1])
                        1'b0: begin
                            store_data_aligned = {16'h0000, store_data[15:0]};
                            byte_enable = 4'b0011;
                        end
                        1'b1: begin
                            store_data_aligned = {store_data[15:0], 16'h0000};
                            byte_enable = 4'b1100;
                        end
                    endcase
                end
                
                FUNCT3_WORD: begin
                    // SW - Store Word
                    store_data_aligned = store_data;
                    byte_enable = 4'b1111;
                end
                
                default: begin
                    store_data_aligned = 32'h00000000;
                    byte_enable = 4'b0000;
                end
            endcase
        end else begin
            store_data_aligned = 32'h00000000;
            byte_enable = 4'b0000;
        end
    end

endmodule