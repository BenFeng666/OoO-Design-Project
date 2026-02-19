module DataMemory (
    input wire clk,
    input wire reset,
    
    // Control Signals
    input wire MemWrite,        // Enable writing (for Store instructions)
    input wire MemRead,         // Enable reading (for Load instructions)
    
    // Data & Address
    input wire [31:0] Address,  // Calculated by ALU (e.g., rs1 + imm)
    input wire [31:0] Write_Data, // Data to write (from rs2)
    
    // Output
    output wire [31:0] Read_Data // Data read from memory
);

    // Memory Array: 1024 words (4KB total size)
    // You can adjust the size [0:X] as needed
    reg [31:0] d_mem [0:1023];
    integer i;

    // --------------------------------------------------------
    // Word Alignment & Reading
    // --------------------------------------------------------
    // Like I-Cache, we drop the bottom 2 bits to convert byte address 
    // to word index (Address / 4).
    // If MemRead is 0, we output 0 (safety).
    assign Read_Data = (MemRead) ? d_mem[Address[11:2]] : 32'b0;

    // --------------------------------------------------------
    // Synchronous Writing
    // --------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Clear memory on reset
            for (i=0; i<1024; i=i+1) d_mem[i] <= 32'b0;
        end
        else if (MemWrite) begin
            // Write to the specific word index
            d_mem[Address[11:2]] <= Write_Data;
            
            // Debugging: Print to console when writing
            $display("D-Cache: Wrote %h to Address %h", Write_Data, Address);
        end
    end

endmodule
