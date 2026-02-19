// Program Counter (PC) Module for RV32I Single-Cycle Core
// Stores and updates the program counter on each clock cycle

module pc #(
    parameter RESET_ADDR = 32'h00000000  // Initial PC value on reset
) (
    input  logic        clock,           // Clock signal
    input  logic        reset,           // Reset signal (active high)
    input  logic [31:0] pc_next,         // Next PC value (from control logic)
    output logic [31:0] pc_current       // Current PC value
);

    // PC register - updates on positive clock edge
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            pc_current <= RESET_ADDR;
        end else begin
            pc_current <= pc_next;
        end
    end

endmodule