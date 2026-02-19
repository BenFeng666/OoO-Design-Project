module InstructionMemory (
    input wire [31:0] pc,          // The current Program Counter address
    output wire [31:0] instruction // The instruction at that address
);

    // Define Memory Size: 1024 words (4KB)
    // You can increase this size if your program is larger.
    reg [31:0] mem [0:1023]; 

    // --------------------------------------------------------
    // Word Alignment Logic
    // --------------------------------------------------------
    // The PC increments by 4 (bytes), but our memory array is indexed by 
    // "Word" (lines). We drop the bottom 2 bits (divide by 4) to map 
    // the byte address to the word index.
    // Example: PC=0 -> index 0. PC=4 -> index 1.
    assign instruction = mem[pc[11:2]];

    // --------------------------------------------------------
    // Program Loader (Simulation Only)
    // --------------------------------------------------------
    // This block loads your machine code from a hex file into the memory
    // array when the simulation starts.
    initial begin
        // Change "program.hex" to the name of your machine code file
        $readmemh("program.hex", mem);
    end

endmodule
