module issue_queue (
    input wire clk,
    input wire rst,
    input wire dispatch_valid,
    input wire [3:0]  dispatch_op,
    input wire dispatch_src1_ready,
    input wire [2:0]  dispatch_src1_tag,
    input wire [31:0] dispatch_src1_value,
    input wire dispatch_src2_ready,
    input wire [2:0]  dispatch_src2_tag,
    input wire [31:0] dispatch_src2_value,
    input wire [2:0]  dispatch_dest_tag,
    input wire imm_valid,
    input wire [31:0] imm_value,
    input wire [31:0] PC,
    input wire [31:0] pc_4,
    input wire cdb_valid0,
    input wire [2:0]  cdb_tag0,
    input wire [31:0] cdb_value0,
    input wire alu0_busy,
    input wire alu0_done,
    input wire dispatch_use_imm,
    input wire dispatch_reg_write,
    input wire dispatch_mem_read,
    input wire dispatch_mem_write,
    input wire dispatch_branch,
    input wire dispatch_jump,
    input wire dispatch_jump_reg,
    output wire iq_full,
    input wire flush,

    // issue slot 0
    output reg         issue_valid0,
    output reg [3:0]   issue_alu_op0,
    output reg [31:0]  issue_src10,
    output reg [31:0]  issue_src20,
    output reg [31:0]  issue_src30,
    output reg [31:0]  issue_imm0,
    output reg [31:0]  issue_pc0,
    output reg [31:0]  issue_pc_plus40,
    output reg         issue_use_imm0,
    output reg         issue_reg_write0,
    output reg         issue_mem_read0,
    output reg         issue_mem_write0,
    output reg         issue_branch0,
    output reg         issue_jump0,
    output reg         issue_jump_reg0,
    output reg [2:0]   issue_dest_tag0,

    // issue slot 1
    output reg         issue_valid1,
    output reg [3:0]   issue_alu_op1,
    output reg [31:0]  issue_src11,
    output reg [31:0]  issue_src21,
    output reg [31:0]  issue_src31,
    output reg [31:0]  issue_imm1,
    output reg [31:0]  issue_pc1,
    output reg [31:0]  issue_pc_plus41,
    output reg         issue_use_imm1,
    output reg         issue_reg_write1,
    output reg         issue_mem_read1,
    output reg         issue_mem_write1,
    output reg         issue_branch1,
    output reg         issue_jump1,
    output reg         issue_jump_reg1,
    output reg [2:0]   issue_dest_tag1,
    input wire         issue1_accept
);

// IQ entry format (151 bits total)
// [150]     : valid bit
// [149]     : use_imm
// [148]     : reg_write
// [147]     : mem_read
// [146]     : mem_write
// [145]     : branch
// [144]     : jump
// [143]     : jump_reg
// [142:140] : dest_tag
// [139:136] : op
// [135:104] : pc
// [103:72]  : imm
// [71]      : src2_ready
// [70:68]   : src2_tag
// [67:36]   : src2_value
// [35]      : src1_ready
// [34:32]   : src1_tag
// [31:0]    : src1_value

reg [150:0] IQ [7:0];

integer i, k, j;
assign iq_full = (IQ[0][150] && IQ[1][150] && IQ[2][150] && IQ[3][150] &&
                  IQ[4][150] && IQ[5][150] && IQ[6][150] && IQ[7][150]);

reg [2:0] issue_idx0;
reg [2:0] issue_idx1;
reg [2:0] alu0_exec_idx;

always @(*) begin
    issue_valid0 = 1'b0;
    issue_valid1 = 1'b0;
    issue_idx0 = 3'b0;
    issue_idx1 = 3'b0;

    issue_src30 = 32'b0;
    issue_src31 = 32'b0;
    issue_pc_plus40 = 32'b0;
    issue_pc_plus41 = 32'b0;

    issue_src10 = 32'b0;
    issue_src20 = 32'b0;
    issue_src11 = 32'b0;
    issue_src21 = 32'b0;

    issue_imm0 = 32'b0;
    issue_imm1 = 32'b0;
    issue_pc0 = 32'b0;
    issue_pc1 = 32'b0;

    issue_alu_op0 = 4'b0;
    issue_alu_op1 = 4'b0;
    issue_dest_tag0 = 3'b0;
    issue_dest_tag1 = 3'b0;

    issue_use_imm0 = 1'b0;
    issue_use_imm1 = 1'b0;
    issue_reg_write0 = 1'b0;
    issue_reg_write1 = 1'b0;
    issue_mem_read0 = 1'b0;
    issue_mem_read1 = 1'b0;
    issue_mem_write0 = 1'b0;
    issue_mem_write1 = 1'b0;
    issue_branch0 = 1'b0;
    issue_branch1 = 1'b0;
    issue_jump0 = 1'b0;
    issue_jump1 = 1'b0;
    issue_jump_reg0 = 1'b0;
    issue_jump_reg1 = 1'b0;

    // ALU0 : MUL only
    for (j = 0; j < 8; j = j + 1) begin
        if (!issue_valid0 &&
            !alu0_busy &&
            IQ[j][150] &&
            IQ[j][35] &&
            IQ[j][71] &&
            (IQ[j][139:136] == 4'b1011)) begin

            issue_valid0      = 1'b1;
            issue_idx0        = j[2:0];
            issue_src10       = IQ[j][31:0];
            issue_src20       = IQ[j][67:36];
            issue_imm0        = IQ[j][103:72];
            issue_pc0         = IQ[j][135:104];
            issue_alu_op0     = IQ[j][139:136];
            issue_dest_tag0   = IQ[j][142:140];
            issue_jump_reg0   = IQ[j][143];
            issue_jump0       = IQ[j][144];
            issue_branch0     = IQ[j][145];
            issue_mem_write0  = IQ[j][146];
            issue_mem_read0   = IQ[j][147];
            issue_reg_write0  = IQ[j][148];
            issue_use_imm0    = IQ[j][149];
        end
    end

    // ALU1 : everything except MUL
    for (j = 0; j < 8; j = j + 1) begin
        if (!issue_valid1 &&
            IQ[j][150] &&
            IQ[j][35] &&
            IQ[j][71] &&
            (IQ[j][139:136] != 4'b1011)) begin

            issue_valid1      = 1'b1;
            issue_idx1        = j[2:0];
            issue_src11       = IQ[j][31:0];
            issue_src21       = IQ[j][67:36];
            issue_imm1        = IQ[j][103:72];
            issue_pc1         = IQ[j][135:104];
            issue_alu_op1     = IQ[j][139:136];
            issue_dest_tag1   = IQ[j][142:140];
            issue_jump_reg1   = IQ[j][143];
            issue_jump1       = IQ[j][144];
            issue_branch1     = IQ[j][145];
            issue_mem_write1  = IQ[j][146];
            issue_mem_read1   = IQ[j][147];
            issue_reg_write1  = IQ[j][148];
            issue_use_imm1    = IQ[j][149];
        end
    end
end

always @(posedge clk or negedge rst) begin
    if (!rst) begin
        for (i = 0; i < 8; i = i + 1)
            IQ[i] <= 151'b0;
        alu0_exec_idx <= 3'b0;
    end
    else if (flush) begin
        for (i = 0; i < 8; i = i + 1)
            IQ[i] <= 151'b0;
        alu0_exec_idx <= 3'b0;
    end
    else begin
        // dispatch
        if (dispatch_valid && !iq_full) begin : dispatch_loop
            for (i = 0; i < 8; i = i + 1) begin
                if (!IQ[i][150]) begin
                    // src1
                    if (dispatch_src1_ready) begin
                        IQ[i][35]    <= 1'b1;
                        IQ[i][34:32] <= 3'b0;
                        IQ[i][31:0]  <= dispatch_src1_value;
                    end
                    else if (cdb_valid0 && (dispatch_src1_tag == cdb_tag0)) begin
                        IQ[i][35]    <= 1'b1;
                        IQ[i][34:32] <= 3'b0;
                        IQ[i][31:0]  <= cdb_value0;
                    end
                    else begin
                        IQ[i][35]    <= 1'b0;
                        IQ[i][34:32] <= dispatch_src1_tag;
                        IQ[i][31:0]  <= 32'b0;
                    end

                    // src2
                    if (dispatch_src2_ready) begin
                        IQ[i][71]    <= 1'b1;
                        IQ[i][70:68] <= 3'b0;
                        IQ[i][67:36] <= dispatch_src2_value;
                    end
                    else if (cdb_valid0 && (dispatch_src2_tag == cdb_tag0)) begin
                        IQ[i][71]    <= 1'b1;
                        IQ[i][70:68] <= 3'b0;
                        IQ[i][67:36] <= cdb_value0;
                    end
                    else begin
                        IQ[i][71]    <= 1'b0;
                        IQ[i][70:68] <= dispatch_src2_tag;
                        IQ[i][67:36] <= 32'b0;
                    end

                    IQ[i][139:136] <= dispatch_op;
                    IQ[i][142:140] <= dispatch_dest_tag;
                    IQ[i][150]     <= 1'b1;
                    IQ[i][149]     <= dispatch_use_imm;
                    IQ[i][148]     <= dispatch_reg_write;
                    IQ[i][147]     <= dispatch_mem_read;
                    IQ[i][146]     <= dispatch_mem_write;
                    IQ[i][145]     <= dispatch_branch;
                    IQ[i][144]     <= dispatch_jump;
                    IQ[i][143]     <= dispatch_jump_reg;
                    IQ[i][135:104] <= PC;
                    IQ[i][103:72]  <= imm_value;

                    disable dispatch_loop;
                end
            end
        end

        // wakeup from CDB
        if (cdb_valid0) begin
            for (k = 0; k < 8; k = k + 1) begin
                if ((cdb_tag0 == IQ[k][34:32]) && IQ[k][150] && !IQ[k][35]) begin
                    IQ[k][31:0] <= cdb_value0;
                    IQ[k][35]   <= 1'b1;
                end

                if ((cdb_tag0 == IQ[k][70:68]) && IQ[k][150] && !IQ[k][71]) begin
                    IQ[k][67:36] <= cdb_value0;
                    IQ[k][71]    <= 1'b1;
                end
            end
        end

        // ALU0 entry is cleared only when ALU0 actually finishes
        if (issue_valid0)
            alu0_exec_idx <= issue_idx0;

        if (alu0_done)
            IQ[alu0_exec_idx] <= 151'b0;

        // slot1 entry is cleared only when top accepts it
        if (issue_valid1 && issue1_accept)
            IQ[issue_idx1] <= 151'b0;
    end
end

endmodule
