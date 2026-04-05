// ============================================================================
// instruction_rom.sv — RV32I Instruction ROM (Synchronous Read)
// ============================================================================
// Read-only instruction memory for the OoO educational CPU.
//
// SYNCHRONOUS READ: the fetch unit presents a byte address on `addr` and
// asserts `en`.  On the next rising edge of `clk`, the instruction appears
// on `instr`.  This one-cycle read latency must be accounted for by the
// fetch unit.
//
// Why synchronous?  Xilinx Vivado infers block RAM (BRAM) from registered
// reads.  A combinational read would force distributed ROM / LUT RAM,
// which is wasteful for anything beyond a few dozen words.
//
// Initialization:
//   $readmemh() from a parameterized hex file.  Supported by both Icarus
//   Verilog (simulation) and Vivado (BRAM init in synthesis).
//
// Out-of-range addresses:
//   When the byte address is >= ROM_DEPTH*4, the output is forced to
//   32'h0000_0000 and addr_valid is set to 0.  There is NO wraparound.
//   32'h0 is not a valid RV32I instruction, so the decode unit will
//   flag it as ITYPE_ILLEGAL.
//
// Uninitialized / zero words:
//   The ROM is zero-filled before $readmemh.  32'h0000_0000 is NOT a
//   valid RV32I instruction.  The decode unit must treat it as illegal.
//   This makes runaway PCs and buffer overruns immediately visible.
// ============================================================================

module instruction_rom #(
    parameter int ROM_DEPTH = 256,              // Number of 32-bit words
    parameter int DATA_W    = 32,
    parameter int ADDR_W    = 32,               // Byte-address width (matches PC)
    parameter     MEM_FILE  = "program.hex"     // Hex file for $readmemh
)(
    input  logic              clk,
    input  logic              en,               // Read enable (stall when low)

    input  logic [ADDR_W-1:0] addr,             // Byte address (word-aligned PC)
    output logic [DATA_W-1:0] instr,            // Instruction (available 1 cycle after addr/en)
    output logic              addr_valid        // High when addr was within ROM range
);

    // ----------------------------------------------------------------
    // Derived constants
    // ----------------------------------------------------------------
    localparam int IDX_W         = $clog2(ROM_DEPTH);
    localparam int ROM_BYTE_SIZE = ROM_DEPTH * 4;   // Total byte span

    // ----------------------------------------------------------------
    // Storage — explicit unpacked range for tool compatibility
    // ----------------------------------------------------------------
    logic [DATA_W-1:0] rom [0:ROM_DEPTH-1];

    // ----------------------------------------------------------------
    // Initialization
    // ----------------------------------------------------------------
    initial begin
        for (int i = 0; i < ROM_DEPTH; i++) begin
            rom[i] = {DATA_W{1'b0}};
        end
        $readmemh(MEM_FILE, rom);
    end

    // ----------------------------------------------------------------
    // Address validity (combinational helper)
    // ----------------------------------------------------------------
    logic addr_in_range;
    assign addr_in_range = (addr < ROM_BYTE_SIZE[ADDR_W-1:0]);

    // ----------------------------------------------------------------
    // Word index from byte address
    // ----------------------------------------------------------------
    // Drop bits [1:0] (byte offset within word — assumed zero for
    // word-aligned PCs) and take IDX_W bits for the array index.
    // This index is only used when addr_in_range is true.
    // ----------------------------------------------------------------
    wire [IDX_W-1:0] word_idx = addr[IDX_W+1:2];

    // ----------------------------------------------------------------
    // Synchronous read
    // ----------------------------------------------------------------
    // When en is high:
    //   - In-range address:  instr = ROM contents, addr_valid = 1
    //   - Out-of-range addr: instr = 32'h0,        addr_valid = 0
    // When en is low:
    //   - Both outputs hold their previous values.
    // ----------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (en) begin
            if (addr_in_range) begin
                instr      <= rom[word_idx];
                addr_valid <= 1'b1;
            end else begin
                instr      <= {DATA_W{1'b0}};
                addr_valid <= 1'b0;
            end
        end
        // When en is low, instr and addr_valid hold their previous values.
    end

endmodule
