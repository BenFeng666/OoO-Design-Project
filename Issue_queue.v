module issue_queue (
    input wire clk,
    input wire rst,
    input wire dispatch_valid,
    input wire [3:0]  dispatch_op, // ALU operation (from decoder)
    input wire dispatch_src1_ready,
    input wire [2:0]  dispatch_src1_tag,
    input wire [31:0] dispatch_src1_value,
    input wire dispatch_src2_ready,
    input wire [2:0]  dispatch_src2_tag,
    input wire [31:0] dispatch_src2_value,
    input wire [2:0]  dispatch_dest_tag,   // ROB index
    input wire cdb_valid,
    input wire [2:0]  cdb_tag,
    input wire [31:0] cdb_value,
    output wire iq_full,
    output reg issue_valid,
    output reg [3:0]  issue_op,
    output reg [31:0] issue_src1,
    output reg [31:0] issue_src2,
    output reg [2:0]  issue_dest_tag
);

// IQ entry format (80 bits total)
// [79]      : valid bit (1 = occupied, 0 = free)
//
// Source 1:
// [0]       : src1_ready (1 = value ready, 0 = waiting on CDB)
// [3:1]     : src1_tag   (ROB tag if not ready)
// [35:4]    : src1_value (32-bit operand)
//
// Source 2:
// [36]      : src2_ready
// [39:37]   : src2_tag
// [71:40]   : src2_value
//
// Operation + destination:
// [75:72]   : op (ALU control)
// [78:76]   : dest_tag (ROB index for writeback)

reg [79:0] IQ [7:0]; // ready bit + tag (if have) + value 
reg [2:0] tail;

integer i,k,j;
assign iq_full = (IQ[0][79] && IQ[1][79] && IQ[2][79] && IQ[3][79] &&
                 IQ[4][79] && IQ[5][79] && IQ[6][79] && IQ[7][79]);
reg found_issue;
reg [2:0] issue_idx;

// Combinational issue select logic:
// - Scans IQ entries from low index to high index
// - Selects the FIRST instruction that:
//     valid == 1 AND src1_ready == 1 AND src2_ready == 1
// - Outputs operands and control signals
// - Also outputs issue_idx so sequential block can clear it
//
// NOTE:
// - Only ONE instruction is issued per cycle
// - found_issue prevents multiple selections

always @(*) begin 
    issue_valid = 1'b0;
    issue_op = 4'b0;
    issue_src1 = 32'b0;
    issue_src2 = 32'b0;
    issue_dest_tag = 3'b0;
    found_issue = 1'b0;
    issue_idx = 3'b0;
    for (j=0; j<8; j++) begin :check_tag
        if (IQ[j][0] && IQ[j][36] && IQ[j][79] && !found_issue) begin
            issue_op = IQ[j][75:72];
            issue_src1 = IQ[j][35:4];
            issue_src2 = IQ[j][71:40];
            //IQ[j]= 80'b0; 
            issue_valid = 1'b1; 
            issue_dest_tag = IQ[j][78:76];  
            issue_idx = j[2:0];
            found_issue = 1'b1; end
    end
end
always @(posedge clk or negedge rst) begin 

    if (!rst) begin
        tail<=0;
        //issue_valid <= 1'b0;
        //issue_op <= 4'b0;
        //issue_src1 <= 32'b0;
        //issue_src2 <= 32'b0;
        //issue_dest_tag <= 3'b0;
        for (i=0; i<8;i++) begin 
            IQ[i] <= 80'b0;
        end
    end
    else begin
        // Dispatch logic:
        // - Finds FIRST empty slot (valid == 0)
        // - Writes new instruction into that slot
        // - Uses disable to stop after inserting one instruction
        //
        // NOTE:
        // - This is NOT FIFO (not using tail anymore)
        // - This behaves like a true issue queue (holes are reused)
                
        if (dispatch_valid && !iq_full) begin : dispatch_loop
    for (i = 0; i < 8; i = i + 1) begin
        if (!IQ[i][79]) begin
            // src1
            if (dispatch_src1_ready) begin
                IQ[i][0]    <= 1'b1;
                IQ[i][3:1]  <= 3'b0;
                IQ[i][35:4] <= dispatch_src1_value;
            end
            else if (cdb_valid && (dispatch_src1_tag == cdb_tag)) begin
                IQ[i][0]    <= 1'b1;
                IQ[i][3:1]  <= 3'b0;
                IQ[i][35:4] <= cdb_value;
            end
            else begin
                IQ[i][0]    <= 1'b0;
                IQ[i][3:1]  <= dispatch_src1_tag;
                IQ[i][35:4] <= 32'b0;
            end

            // src2
            if (dispatch_src2_ready) begin
                IQ[i][36]    <= 1'b1;
                IQ[i][39:37] <= 3'b0;
                IQ[i][71:40] <= dispatch_src2_value;
            end
            else if (cdb_valid && (dispatch_src2_tag == cdb_tag)) begin
                IQ[i][36]    <= 1'b1;
                IQ[i][39:37] <= 3'b0;
                IQ[i][71:40] <= cdb_value;
            end
            else begin
                IQ[i][36]    <= 1'b0;
                IQ[i][39:37] <= dispatch_src2_tag;
                IQ[i][71:40] <= 32'b0;
            end

            IQ[i][75:72] <= dispatch_op;
            IQ[i][78:76] <= dispatch_dest_tag;
            IQ[i][79]    <= 1'b1;
            disable dispatch_loop;
        end
    end
end

        if (cdb_valid) begin
        for (k=0; k<8; k++) begin 
            if ((cdb_tag == IQ[k][3:1]) && IQ[k][79] && !IQ[k][0]) begin 
                IQ[k][35:4] <= cdb_value;
                IQ[k][0] <= 1'b1;
                end
            
            if ((cdb_tag == IQ[k][39:37]) && IQ[k][79] && !IQ[k][36]) begin 
                IQ[k][71:40]<= cdb_value; 
                IQ[k][36]<= 1'b1;
            end
        end
        end
        // Issue commit:
        // - Clears the issued entry (valid = 0)
        // - Happens in sequential block AFTER combinational selection
        //
        // NOTE:
        // - IQ state is only modified in clocked block
        // - Ensures no combinational write to storage (important for synthesis)
        if (issue_valid) begin
            IQ[issue_idx] <= 80'b0;
        end
        
        
    end
end
endmodule
