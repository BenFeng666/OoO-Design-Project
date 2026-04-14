module ROB (
    input wire clk,
    input wire rst,

    input wire dispatch_valid,
    input wire [4:0] dispatch_rd,
    input wire dispatch_reg_write,
    output reg [2:0] dispatch_rob_idx,
    output wire rob_full,
    output wire rob_empty,

    input wire wb_valid,
    input wire [2:0] wb_rob_idx,
    input wire [31:0] wb_value,
    output reg [2:0] commit_rob_idx,
    input wire dispatch_is_store,
    input wire dispatch_is_branch,
    input wire dispatch_is_jump,
    input wire wb_branch_taken,
    input wire [31:0] wb_target,
    input wire [31:0] wb_store_data,

    output reg commit_valid,
    output reg [4:0] commit_addr,
    output reg [31:0] commit_data,
    output reg commit_reg_write,
    input  wire [2:0] lookup_tag1,
    input  wire [2:0] lookup_tag2,
    output wire lookup_valid1,
    output wire lookup_ready1,
    output wire [31:0] lookup_value1,
    output wire lookup_valid2,
    output wire lookup_ready2,
    output wire [31:0] lookup_value2,
    output reg commit_is_store,
    output reg commit_is_branch,
    output reg commit_is_jump,
    output reg commit_branch_taken,
    output reg [31:0] commit_target,
    output reg [31:0] commit_store_data
);

reg valid [7:0];
reg ready [7:0];
reg  reg_write [7:0];
reg is_store [7:0];
reg is_branch [7:0];
reg is_jump [7:0];
reg [4:0] addr [7:0];
reg [31:0] value [7:0];
reg [31:0] target [7:0];
reg branch_taken [7:0];
reg [31:0] store_data [7:0];
reg [2:0] head;
reg [2:0] tail;
reg [3:0] count;
integer i;
assign rob_full = (count == 4'd8);
assign rob_empty = (count == 4'd0);
assign lookup_valid1 = valid[lookup_tag1];
assign lookup_ready1 = ready[lookup_tag1];
assign lookup_value1 = value[lookup_tag1];

assign lookup_valid2 = valid[lookup_tag2];
assign lookup_ready2 = ready[lookup_tag2];
assign lookup_value2 = value[lookup_tag2];

always @(posedge clk or negedge rst) begin
  if (!rst) begin
    dispatch_rob_idx <= 3'b0;
    commit_valid <= 1'b0;
    commit_addr <= 5'b0;
    commit_data <= 32'b0;
    commit_reg_write <= 1'b0;
    for (i=0; i<8; i=i+1) begin
        value[i] <= 32'b0;
        addr[i] <= 5'b0;
        reg_write[i] <= 1'b0;
        valid[i] <= 1'b0;
        ready [i] <= 1'b0;
        is_store[i] <= 1'b0;
        is_branch[i] <= 1'b0;
        is_jump[i] <= 1'b0;
        target[i] <= 32'b0;
        branch_taken[i] <= 1'b0;
        store_data[i] <= 32'b0;

    end
    head <= 3'b0;
    tail <= 3'b0;
    count <= 4'b0;
    commit_rob_idx <= 3'b0;
    commit_is_store <= 1'b0;
    commit_is_branch <= 1'b0;
    commit_is_jump <= 1'b0;
    commit_branch_taken <= 1'b0;
    commit_target <= 32'b0;
    commit_store_data <= 32'b0;
    
  end

  else begin 
    commit_valid <=1'b0;
    commit_addr <= 5'b0;
    commit_data <= 32'b0;
    commit_reg_write <= 1'b0;
    commit_is_store <= 1'b0;
    commit_is_branch <= 1'b0;
    commit_is_jump <= 1'b0;
    commit_branch_taken <= 1'b0;
    commit_target <= 32'b0;
    commit_store_data <= 32'b0;

    if (!rob_full && dispatch_valid) begin
        valid[tail] <=1'b1 ; // Slot is occupied
        ready[tail] <=1'b0; // not ready for commit
        addr[tail] <= dispatch_rd; // store the register address
        reg_write[tail]<= dispatch_reg_write;
        is_store[tail] <= dispatch_is_store;
        is_branch[tail] <= dispatch_is_branch;
        is_jump[tail] <= dispatch_is_jump;
        dispatch_rob_idx <= tail; 
        tail <= tail + 1'b1;                                                                                                                                                                                                                                                                                                                                                                        
        
    end
    
    if (wb_valid) begin
        value[wb_rob_idx] <= wb_value;
        ready[wb_rob_idx] <= 1'b1;
        target[wb_rob_idx] <= wb_target;
        branch_taken[wb_rob_idx] <= wb_branch_taken;
        store_data[wb_rob_idx] <= wb_store_data;
    end
    if ((ready[head]) && (valid[head])) begin
        commit_valid <=1'b1; 
        commit_addr <= addr[head];
        commit_data <= value[head];
        commit_reg_write <= reg_write[head];
        addr[head] <= 5'b0;
        value[head] <= 32'b0;
        reg_write[head] <= 1'b0; 
        head <= head +1'b1; 
        valid[head] <= 1'b0; // that slot is free again
        ready[head] <= 1'b0;
        commit_rob_idx <= head;
        commit_is_store <= is_store[head];
        commit_is_branch <= is_branch[head];
        commit_is_jump <= is_jump[head];
        commit_branch_taken <= branch_taken[head];
        commit_target <= target[head];
        commit_store_data <= store_data[head];
        is_store[head] <= 1'b0;
        is_branch[head] <= 1'b0;
        is_jump[head] <= 1'b0;
        target[head] <= 32'b0;
        branch_taken[head] <= 1'b0;
        store_data[head] <= 32'b0;
         end
    if (!(!rob_full && dispatch_valid) && ((ready[head]) && (valid[head]))) begin 
        count <= count -1; end
    else if (((!rob_full && dispatch_valid) && !((ready[head]) && (valid[head])))) begin 
        count <= count +1; end 
  end
end




endmodule


