// Register File for RV32I Single-Cycle Core
// 32 general-purpose registers (x0-x31)
// x0 is hardwired to zero
// 2 read ports (asynchronous) and 1 write port (synchronous)

module register_file (
    input  logic        clock,           // Clock signal
    input  logic        reset,           // Reset signal (active high)
    
    // Read Port 1 (rs1)
    input  logic [4:0]  read_addr1,      // Read address 1 (rs1)
    output logic [31:0] read_data1,      // Read data 1
    
    // Read Port 2 (rs2)
    input  logic [4:0]  read_addr2,      // Read address 2 (rs2)
    output logic [31:0] read_data2,      // Read data 2
    
    // Write Port (rd)
    input  logic [4:0]  write_addr,      // Write address (rd)
    input  logic [31:0] write_data,      // Write data
    input  logic        write_enable     // Write enable signal
);

    // 32 registers, each 32 bits wide
    logic [31:0] registers [31:0];
    
    // Synchronous write operation
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            // Initialize all registers to zero on reset
            for (int i = 0; i < 32; i++) begin
                registers[i] <= 32'h00000000;
            end
        end else begin
            // Write to register if write_enable is high and address is not x0
            if (write_enable && (write_addr != 5'b00000)) begin
                registers[write_addr] <= write_data;
            end
        end
    end
    
    // Asynchronous read operations
    // x0 is hardwired to zero
    assign read_data1 = (read_addr1 == 5'b00000) ? 32'h00000000 : registers[read_addr1];
    assign read_data2 = (read_addr2 == 5'b00000) ? 32'h00000000 : registers[read_addr2];

endmodule