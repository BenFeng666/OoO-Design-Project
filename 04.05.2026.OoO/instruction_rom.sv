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
//   The word index is truncated to IDX_W bits, so large addresses wrap.
//   An `addr_valid` output is provided so the fetch unit can detect when
//   the PC has left the valid program region [0, ROM_DEPTH*4).
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
    output logic              addr_valid         // High when addr is within ROM range
);

    // ----------------------------------------------------------------
    // Derived constants
    // ----------------------------------------------------------------
    localparam int IDX_W         = $clog2(ROM_DEPTH);
    localparam int ROM_BYTE_SIZE = ROM_DEPTH * 4;   // Total byte span

    // ----------------------------------------------------------------
    // Storage
    // ----------------------------------------------------------------
    logic [DATA_W-1:0] rom [ROM_DEPTH];

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
    // Word index from byte address
    // ----------------------------------------------------------------
    // Drop bits [1:0] (byte offset within word — assumed zero for
    // word-aligned PCs) and take IDX_W bits for the array index.
    // If the full address exceeds ROM_DEPTH*4, the index wraps via
    // truncation.  Use `addr_valid` to detect this case.
    // ----------------------------------------------------------------
    wire [IDX_W-1:0] word_idx = addr[IDX_W+1:2];

    // ----------------------------------------------------------------
    // Address validity
    // ----------------------------------------------------------------
    // Combinational: high when the byte address is strictly less than
    // the ROM's byte size.  Registered alongside instr so both outputs
    // correspond to the same request cycle.
    // ----------------------------------------------------------------
    logic addr_in_range;
    assign addr_in_range = (addr < ROM_BYTE_SIZE[ADDR_W-1:0]);

    // ----------------------------------------------------------------
    // Synchronous read
    // ----------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (en) begin
            instr      <= rom[word_idx];
            addr_valid <= addr_in_range;
        end
        // When en is low, instr and addr_valid hold their previous values.
    end

endmodule
