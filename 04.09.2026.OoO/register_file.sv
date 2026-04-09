`timescale 1ns / 1ps




// ============================================================================
// register_file.sv — RV32I Architectural Register File
// ============================================================================
// Holds committed architectural state (x0–x31) for the OoO CPU.
//
// Role in the pipeline:
//   - READ  at decode/dispatch (combinational, 2 ports)
//   - WRITE at commit from the reorder buffer (synchronous, 1 port)
//
// Write bypass: when a commit write and a decode read target the same
// non-zero register in the same cycle, the read returns the freshly
// committed value (wr_data), not the stale stored value.  This ensures
// the register file always reflects committed truth on its read ports.
//
// This file stores ONLY committed values. Speculative / in-flight values
// live in the reservation station (via tags) and the reorder buffer.
//
// x0 is hardwired to zero: reads always return 0, writes are ignored.
// ============================================================================

module register_file #(
    parameter int NUM_REGS = 32,
    parameter int DATA_W   = 32,
    parameter int ADDR_W   = 5       // log2(NUM_REGS)
)(
    input  logic              clk,
    input  logic              rst_n,    // Active-low synchronous reset

    // --- Read port 1 (rs1) — combinational ---
    input  logic [ADDR_W-1:0] rd_addr1,
    output logic [DATA_W-1:0] rd_data1,

    // --- Read port 2 (rs2) — combinational ---
    input  logic [ADDR_W-1:0] rd_addr2,
    output logic [DATA_W-1:0] rd_data2,

    // --- Write port (commit) — synchronous ---
    input  logic              wr_en,
    input  logic [ADDR_W-1:0] wr_addr,
    input  logic [DATA_W-1:0] wr_data
);

    // ----------------------------------------------------------------
    // Register storage
    // ----------------------------------------------------------------
    logic [DATA_W-1:0] regs [NUM_REGS];

    // ----------------------------------------------------------------
    // Synchronous write + reset
    // ----------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_REGS; i++) begin
                regs[i] <= '0;
            end
        end else if (wr_en && (wr_addr != '0)) begin
            // x0 is hardwired to zero — silently ignore writes to it
            regs[wr_addr] <= wr_data;
        end
    end

    // ----------------------------------------------------------------
    // Combinational reads with write bypass
    // ----------------------------------------------------------------
    // x0 always returns 0.  For all other registers, if a commit write
    // is happening this cycle to the same address, forward wr_data so
    // the read port reflects the freshly committed value immediately.
    // ----------------------------------------------------------------
    logic fwd1, fwd2;

    assign fwd1 = wr_en && (wr_addr != '0) && (wr_addr == rd_addr1);
    assign fwd2 = wr_en && (wr_addr != '0) && (wr_addr == rd_addr2);

    assign rd_data1 = (rd_addr1 == '0) ? '0 :
                      fwd1              ? wr_data :
                                          regs[rd_addr1];

    assign rd_data2 = (rd_addr2 == '0) ? '0 :
                      fwd2              ? wr_data :
                                          regs[rd_addr2];

endmodule


