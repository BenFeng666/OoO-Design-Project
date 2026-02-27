// Execution Unit for RV32I Out-of-Order CPU Core
// Connects Reservation Station to ALU and broadcasts results on CDB
// Single-cycle ALU execution with pipeline register

module execution_unit #(
    parameter ROB_ADDR_WIDTH = 4      // ROB tag width
)(
    input  logic                        clock,
    input  logic                        reset,
    
    // Issue interface from Reservation Station
    input  logic                        issue_valid,        // Instruction issued from RS
    input  logic [3:0]                  issue_alu_op,       // ALU operation
    input  logic [31:0]                 issue_src1_value,   // Source 1 value
    input  logic [31:0]                 issue_src2_value,   // Source 2 value
    input  logic [ROB_ADDR_WIDTH-1:0]   issue_dest_tag,     // Destination ROB tag
    output logic                        issue_ready,        // Ready to accept issue
    
    // Common Data Bus (CDB) - broadcast results
    output logic                        cdb_valid,          // Result valid on CDB
    output logic [ROB_ADDR_WIDTH-1:0]   cdb_tag,            // Result ROB tag
    output logic [31:0]                 cdb_data            // Result data
);

    // ALU signals
    logic [31:0] alu_operand_a;
    logic [31:0] alu_operand_b;
    logic [3:0]  alu_op;
    logic [31:0] alu_result;
    
    // Pipeline register for ALU result
    logic                       result_valid;
    logic [ROB_ADDR_WIDTH-1:0]  result_tag;
    logic [31:0]                result_data;
    
    // Instantiate ALU
    alu alu_inst (
        .operand_a(alu_operand_a),
        .operand_b(alu_operand_b),
        .alu_op(alu_op),
        .result(alu_result)
    );
    
    // Connect issue to ALU inputs
    assign alu_operand_a = issue_src1_value;
    assign alu_operand_b = issue_src2_value;
    assign alu_op        = issue_alu_op;
    
    // Always ready to accept new instruction (single-cycle execution)
    assign issue_ready = 1'b1;
    
    // Pipeline ALU result (1-cycle execution latency)
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            result_valid <= 1'b0;
            result_tag   <= '0;
            result_data  <= 32'b0;
        end else begin
            // Capture issued instruction and ALU result
            result_valid <= issue_valid;
            result_tag   <= issue_dest_tag;
            result_data  <= alu_result;
        end
    end
    
    // Broadcast result on CDB
    assign cdb_valid = result_valid;
    assign cdb_tag   = result_tag;
    assign cdb_data  = result_data;

endmodule