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
    output reg [2:0] commit_rob_idx

    output reg commit_valid,
    output reg [4:0] commit_addr,
    output reg [31:0] commit_data,
    output reg commit_reg_write
);

reg valid [7:0];
reg ready [7:0];
reg  reg_write [7:0];
reg [4:0] addr [7:0];
reg [31:0] value [7:0];

reg [2:0] head;
reg [2:0] tail;
reg [3:0] count;
integer i;
assign rob_full = (count == 4'd8);
assign rob_empty = (count == 4'd0);

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

    end
    head <= 3'b0;
    tail <= 3'b0;
    count <= 4'b0;
    
  end

  else begin 
    commit_valid <=1'b0;
    commit_addr <= 5'b0;
    commit_data <= 32'b0;
    commit_reg_write <= 1'b0;

    if (!rob_full && dispatch_valid) begin
        valid[tail] <=1'b1 ; // Slot is occupied
        ready[tail] <=1'b0; // not ready for commit
        addr[tail] <= dispatch_rd; // store the register address
        reg_write[tail]<= dispatch_reg_write;
        dispatch_rob_idx <= tail; 
        tail <= tail + 1'b1;                                                                                                                                                                                                                                                                                                                                                                        
        
    end
    
    if (wb_valid) begin
        value[wb_rob_idx] <= wb_value;
        ready[wb_rob_idx] <= 1'b1; 
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
        commit_rob_idx = head;
         end
    if (!(!rob_full && dispatch_valid) && ((ready[head]) && (valid[head]))) begin 
        count <= count -1; end
    else if (((!rob_full && dispatch_valid) && !((ready[head]) && (valid[head])))) begin 
        count <= count +1; end 
  end
end




endmodule


