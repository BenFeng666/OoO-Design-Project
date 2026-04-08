module RAT (
    input  wire       clk,
    input  wire       rst,
    input  wire [4:0] rs1,
    input  wire [4:0] rs2,
    input  wire [4:0] rd,
    input  wire       rename_valid,   // dispatching an instruction that writes rd
    input  wire [2:0] rob_idx,
    input  wire       commit_valid,
    input  wire [4:0] commit_reg,
    input  wire [2:0] commit_rob_idx,
    output reg        rs1_renamed,
    output reg [2:0]  rs1_tag,
    output reg        rs2_renamed,
    output reg [2:0]  rs2_tag
);
reg [3:0] RAT [31:0]; // assume RAT have 32 entry and we have 32 register
integer i;

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        for (i=0; i<32;i++) begin 
            RAT[i] <= 4'b0; end
    end
    else begin // for distination register 
        if (rename_valid && rd != 5'd0) begin 
            RAT[rd] <={1'b1, rob_idx};
        end
        if (commit_valid && RAT[commit_reg][3] && (RAT[commit_reg][2:0]==commit_rob_idx)) begin  // if commited
            RAT[commit_reg] <= 4'b0; 
        end
    end

end
always @(*) begin // this is for the alu source 1 and source 2
    if (rs1 == 5'd0) begin 
        rs1_renamed = 1'b0; // disn't renamed
        rs1_tag = 3'b0; // no need to look up in rob
    end
    else begin 
        rs1_renamed = RAT[rs1][3]; // give the renamed or not info
        rs1_tag = RAT[rs1][2:0]; 
    end
    if (rs2 == 5'd0) begin 
        rs2_renamed = 1'b0; // disn't renamed
        rs2_tag = 3'b0; // no need to look up in rob
    end
    else begin 
        rs2_renamed = RAT[rs2][3]; // give the renamed or not info
        rs2_tag = RAT[rs2][2:0]; 
    end


end
endmodule
