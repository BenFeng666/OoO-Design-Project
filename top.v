module top (
    input wire clk,
    input wire rst
);

//
// IF / ID
//
wire [31:0] pc;
wire [31:0] next_pc;
wire [31:0] pc4;
wire [31:0] instruction;

wire [31:0] id_instruction;
wire [31:0] id_pc;
wire [31:0] id_pc4;

//
// Decode
//
wire [31:0] rs1_data;
wire [31:0] rs2_data;
wire [31:0] imm;
wire [3:0]  alu_ctrl;

wire        WE;
wire        ALUSrc;
wire        MemRead;
wire        MemWrite;
wire        MemtoReg;
wire        Branch;
wire        jump;

//
// RAT
//
wire        rs1_renamed;
wire [2:0]  rs1_tag;
wire        rs2_renamed;
wire [2:0]  rs2_tag;

//
// ROB
//
wire [2:0]  dispatch_rob_idx;
wire        rob_full;
wire        rob_empty;

wire        commit_valid;
wire [4:0]  commit_addr;
wire [31:0] commit_data;
wire        commit_reg_write;
wire [2:0]  commit_rob_idx;

wire        commit_is_store;
wire        commit_is_branch;
wire        commit_is_jump;
wire        commit_branch_taken;
wire [31:0] commit_target;
wire [31:0] commit_store_data;

wire        rob_lookup_valid1;
wire        rob_lookup_ready1;
wire [31:0] rob_lookup_value1;

wire        rob_lookup_valid2;
wire        rob_lookup_ready2;
wire [31:0] rob_lookup_value2;

//
// Dispatch side
//
wire        dispatch_valid_iq;
wire [3:0]  dispatch_op;
wire [2:0]  dispatch_dest_tag;

reg         dispatch_src1_ready;
reg  [2:0]  dispatch_src1_tag;
reg  [31:0] dispatch_src1_value;

reg         dispatch_src2_ready;
reg  [2:0]  dispatch_src2_tag;
reg  [31:0] dispatch_src2_value;

wire        dispatch_use_imm;
wire        dispatch_reg_write;
wire        dispatch_mem_read;
wire        dispatch_mem_write;
wire        dispatch_branch;
wire        dispatch_jump;
wire        dispatch_jump_reg;
wire        imm_valid;

//
// Issue queue outputs: slot 0
//
wire        issue_valid0;
wire [3:0]  issue_alu_op0;
wire [31:0] issue_src10;
wire [31:0] issue_src20;
wire [31:0] issue_src30;
wire [31:0] issue_imm0;
wire [31:0] issue_pc0;
wire [31:0] issue_pc_plus40;
wire        issue_use_imm0;
wire        issue_reg_write0;
wire        issue_mem_read0;
wire        issue_mem_write0;
wire        issue_branch0;
wire        issue_jump0;
wire        issue_jump_reg0;
wire [2:0]  issue_dest_tag0;

//
// Issue queue outputs: slot 1
//
wire        issue_valid1;
wire [3:0]  issue_alu_op1;
wire [31:0] issue_src11;
wire [31:0] issue_src21;
wire [31:0] issue_src31;
wire [31:0] issue_imm1;
wire [31:0] issue_pc1;
wire [31:0] issue_pc_plus41;
wire        issue_use_imm1;
wire        issue_reg_write1;
wire        issue_mem_read1;
wire        issue_mem_write1;
wire        issue_branch1;
wire        issue_jump1;
wire        issue_jump_reg1;
wire [2:0]  issue_dest_tag1;

wire        iq_full;

//
// ALU0 / ALU1
//
wire [31:0] alu0_result;
wire        alu0_zero;
wire        alu0_negative;

wire [31:0] alu1_result;
wire        alu1_zero;
wire        alu1_negative;

wire        alu0_busy;
wire        alu0_done;
wire [31:0] alu0_wb_value;
wire [2:0]  alu0_wb_tag;

assign alu0_result = alu0_wb_value;

//
// CDB
//
wire [31:0] buffered_cdb_value;
wire [2:0]  buffered_cdb_tag;
wire        buffered_cdb_valid;

wire        cdb_valid0;
wire [2:0]  cdb_tag0;
wire [31:0] cdb_value0;

assign cdb_valid0 = buffered_cdb_valid;
assign cdb_tag0   = buffered_cdb_tag;
assign cdb_value0 = buffered_cdb_value;

//
// Memory / branch-store metadata
//
wire [31:0] data_mem_addr;
wire [31:0] data_mem_wdata;
wire [31:0] data_mem_rdata;

wire [31:0] alu1_cdb_result;
wire        wb_branch_taken;
wire [31:0] wb_target;
wire [31:0] wb_store_data;

wire        ex1_branch_taken;
wire [31:0] ex1_target;
wire [31:0] ex1_store_data;
wire [31:0] ex1_wb_value;

//
// PC mux control
//
wire [31:0] branch_target;
wire [31:0] jal_target;
wire [1:0]  pc_sel;

//
// Front-end dispatch control
//
assign dispatch_valid_iq = !rob_full && !iq_full &&
                           (id_instruction != 32'b0) &&
                           (id_instruction != 32'h00000013) &&
                           (^id_instruction !== 1'bx);

assign dispatch_op        = alu_ctrl;
assign dispatch_dest_tag  = dispatch_rob_idx;
assign dispatch_use_imm   = ALUSrc;
assign dispatch_reg_write = WE;
assign dispatch_mem_read  = MemRead;
assign dispatch_mem_write = MemWrite;
assign dispatch_branch    = Branch;
assign dispatch_jump      = jump;
assign dispatch_jump_reg  = 1'b0;
assign imm_valid          = 1'b1;

//
// ALU1 execute-side metadata
// beq only for branch decision right now
//
assign ex1_branch_taken = issue_branch1 && (issue_src11 == issue_src21);

assign ex1_target =
    issue_jump1      ? (issue_pc1 + issue_imm1) :
    issue_branch1    ? (issue_pc1 + issue_imm1) :
    issue_mem_read1  ? alu1_result :
    issue_mem_write1 ? alu1_result :
                       32'b0;

// store data should be original rs2 value
assign ex1_store_data = issue_src21;

// jal writes PC+4 into rd
assign ex1_wb_value =
    issue_jump1      ? (issue_pc1 + 32'd4) :
    issue_mem_read1  ? data_mem_rdata :
                       alu1_result;

assign alu1_cdb_result = ex1_wb_value;

assign wb_branch_taken = ex1_branch_taken;
assign wb_target       = ex1_target;
assign wb_store_data   = ex1_store_data;

//
// Memory path
// loads read at ALU1 execute, stores write at commit
//
assign data_mem_addr  = (commit_valid && commit_is_store) ? commit_target : alu1_result;
assign data_mem_wdata = commit_store_data;

//
// PC control
// use ROB commit result, not decode-stage jump/branch
//
assign pc4 = pc + 32'd4;
assign branch_target = commit_target;
assign jal_target    = commit_target;

assign pc_sel =
    (commit_valid && commit_is_jump) ? 2'b10 :
    (commit_valid && commit_is_branch && commit_branch_taken) ? 2'b01 :
    2'b00;

//
// Core frontend
//
PC u_pc (
    .clk(clk),
    .rst(rst),
    .next_inst(next_pc),
    .pc(pc)
);

PC_mux u_pc_mux (
    .PC4(pc4),
    .branch_target(branch_target),
    .jal_target(jal_target),
    .pc_sel(pc_sel),
    .next_pc(next_pc)
);

instruction_mem u_imem (
    .addr(pc),
    .instruction(instruction)
);

IF_ID u_if_id (
    .clk(clk),
    .rst(rst),
    .PC(pc),
    .instruction(instruction),
    .PC_4(pc4),
    .ID_instruction(id_instruction),
    .ID_PC(id_pc),
    .ID_PC_4(id_pc4)
);

mcu u_mcu (
    .instruction(id_instruction),
    .WE(WE),
    .ALUSrc(ALUSrc),
    .MemRead(MemRead),
    .MemWrite(MemWrite),
    .MemtoReg(MemtoReg),
    .Branch(Branch),
    .jump(jump)
);

imm_gen u_imm_gen (
    .instruction(id_instruction),
    .imm(imm)
);

ALU_ctrl u_alu_ctrl (
    .instruction(id_instruction),
    .ctrl(alu_ctrl)
);

//
// Architectural register file
//
reg_file u_reg_file (
    .clk(clk),
    .we(commit_valid && commit_reg_write),
    .rst(rst),
    .rs1_addr(id_instruction[19:15]),
    .rs2_addr(id_instruction[24:20]),
    .rd_addr(commit_addr),
    .rd_data(commit_data),
    .rs1_data(rs1_data),
    .rs2_data(rs2_data)
);

//
// Data memory
//
data_mem u_data_mem (
    .clk(clk),
    .rst(rst),
    .mem_read(issue_valid1 && issue_mem_read1),
    .mem_write(commit_valid && commit_is_store),
    .address(data_mem_addr),
    .write_data(data_mem_wdata),
    .read_data(data_mem_rdata)
);

//
// CDB buffer
//
CDB_buffer u_cdb_buffer (
    .clk(clk),
    .rst(rst),

    .ALU0_result(alu0_wb_value),
    .ALU0_tag(alu0_wb_tag),
    .ALU0_valid(alu0_done),

    .ALU1_result(alu1_cdb_result),
    .ALU1_tag(issue_dest_tag1),
    .ALU1_valid(issue_valid1),

    .cdb_value(buffered_cdb_value),
    .cdb_tag(buffered_cdb_tag),
    .cdb_valid(buffered_cdb_valid)
);

//
// RAT
//
RAT u_rat (
    .clk(clk),
    .rst(rst),
    .rs1(id_instruction[19:15]),
    .rs2(id_instruction[24:20]),
    .rd(id_instruction[11:7]),
    .rename_valid(dispatch_valid_iq && WE),
    .rob_idx(dispatch_rob_idx),
    .commit_valid(commit_valid),
    .commit_reg(commit_addr),
    .commit_rob_idx(commit_rob_idx),
    .rs1_renamed(rs1_renamed),
    .rs1_tag(rs1_tag),
    .rs2_renamed(rs2_renamed),
    .rs2_tag(rs2_tag)
);

//
// ROB
//
ROB u_rob (
    .clk(clk),
    .rst(rst),

    .dispatch_valid(dispatch_valid_iq),
    .dispatch_rd(id_instruction[11:7]),
    .dispatch_reg_write(dispatch_reg_write),
    .dispatch_rob_idx(dispatch_rob_idx),
    .rob_full(rob_full),
    .rob_empty(rob_empty),

    .wb_valid(cdb_valid0),
    .wb_rob_idx(cdb_tag0),
    .wb_value(cdb_value0),
    .commit_rob_idx(commit_rob_idx),

    .dispatch_is_store(dispatch_mem_write),
    .dispatch_is_branch(dispatch_branch),
    .dispatch_is_jump(dispatch_jump),
    .wb_branch_taken(wb_branch_taken),
    .wb_target(wb_target),
    .wb_store_data(wb_store_data),

    .commit_valid(commit_valid),
    .commit_addr(commit_addr),
    .commit_data(commit_data),
    .commit_reg_write(commit_reg_write),

    .lookup_tag1(rs1_tag),
    .lookup_tag2(rs2_tag),
    .lookup_valid1(rob_lookup_valid1),
    .lookup_ready1(rob_lookup_ready1),
    .lookup_value1(rob_lookup_value1),
    .lookup_valid2(rob_lookup_valid2),
    .lookup_ready2(rob_lookup_ready2),
    .lookup_value2(rob_lookup_value2),

    .commit_is_store(commit_is_store),
    .commit_is_branch(commit_is_branch),
    .commit_is_jump(commit_is_jump),
    .commit_branch_taken(commit_branch_taken),
    .commit_target(commit_target),
    .commit_store_data(commit_store_data)
);

//
// Issue queue
//
issue_queue u_issue_queue (
    .clk(clk),
    .rst(rst),

    .dispatch_valid(dispatch_valid_iq),
    .dispatch_op(dispatch_op),
    .dispatch_src1_ready(dispatch_src1_ready),
    .dispatch_src1_tag(dispatch_src1_tag),
    .dispatch_src1_value(dispatch_src1_value),
    .dispatch_src2_ready(dispatch_src2_ready),
    .dispatch_src2_tag(dispatch_src2_tag),
    .dispatch_src2_value(dispatch_src2_value),
    .dispatch_dest_tag(dispatch_dest_tag),

    .imm_valid(imm_valid),
    .imm_value(imm),
    .PC(id_pc),
    .pc_4(id_pc4),

    .cdb_valid0(cdb_valid0),
    .cdb_tag0(cdb_tag0),
    .cdb_value0(cdb_value0),

    .dispatch_use_imm(dispatch_use_imm),
    .dispatch_reg_write(dispatch_reg_write),
    .dispatch_mem_read(dispatch_mem_read),
    .dispatch_mem_write(dispatch_mem_write),
    .dispatch_branch(dispatch_branch),
    .dispatch_jump(dispatch_jump),
    .dispatch_jump_reg(dispatch_jump_reg),

    .iq_full(iq_full),

    .issue_valid0(issue_valid0),
    .issue_alu_op0(issue_alu_op0),
    .issue_src10(issue_src10),
    .issue_src20(issue_src20),
    .issue_src30(issue_src30),
    .issue_imm0(issue_imm0),
    .issue_pc0(issue_pc0),
    .issue_pc_plus40(issue_pc_plus40),
    .issue_use_imm0(issue_use_imm0),
    .issue_reg_write0(issue_reg_write0),
    .issue_mem_read0(issue_mem_read0),
    .issue_mem_write0(issue_mem_write0),
    .issue_branch0(issue_branch0),
    .issue_jump0(issue_jump0),
    .issue_jump_reg0(issue_jump_reg0),
    .issue_dest_tag0(issue_dest_tag0),

    .issue_valid1(issue_valid1),
    .issue_alu_op1(issue_alu_op1),
    .issue_src11(issue_src11),
    .issue_src21(issue_src21),
    .issue_src31(issue_src31),
    .issue_imm1(issue_imm1),
    .issue_pc1(issue_pc1),
    .issue_pc_plus41(issue_pc_plus41),
    .issue_use_imm1(issue_use_imm1),
    .issue_reg_write1(issue_reg_write1),
    .issue_mem_read1(issue_mem_read1),
    .issue_mem_write1(issue_mem_write1),
    .issue_branch1(issue_branch1),
    .issue_jump1(issue_jump1),
    .issue_jump_reg1(issue_jump_reg1),
    .issue_dest_tag1(issue_dest_tag1),

    .alu0_busy(alu0_busy),
    .alu0_done(alu0_done)
);

//
// ALUs
//
ALU0 u_alu0 (
    .clk(clk),
    .rst(rst),
    .start(issue_valid0),
    .A(issue_src10),
    .B(issue_use_imm0 ? issue_imm0 : issue_src20),
    .ctrl(issue_alu_op0),
    .in_tag(issue_dest_tag0),
    .wb_value(alu0_wb_value),
    .wb_tag(alu0_wb_tag),
    .zero(alu0_zero),
    .negative(alu0_negative),
    .busy(alu0_busy),
    .done(alu0_done)
);

ALU1 u_alu1 (
    .A(issue_src11),
    .B(issue_use_imm1 ? issue_imm1 : issue_src21),
    .ctrl(issue_alu_op1),
    .result(alu1_result),
    .zero(alu1_zero),
    .negative(alu1_negative)
);

//
// Dispatch operand 1 lookup
//
always @(*) begin
    dispatch_src1_ready = 1'b0;
    dispatch_src1_tag   = rs1_tag;
    dispatch_src1_value = 32'b0;

    case (rs1_renamed)
        1'b0: begin
            dispatch_src1_ready = 1'b1;
            dispatch_src1_value = rs1_data;
        end

        1'b1: begin
            if (rob_lookup_valid1 && rob_lookup_ready1) begin
                dispatch_src1_ready = 1'b1;
                dispatch_src1_value = rob_lookup_value1;
            end else begin
                dispatch_src1_ready = 1'b0;
                dispatch_src1_tag   = rs1_tag;
            end
        end

        default: begin
            dispatch_src1_ready = 1'b0;
            dispatch_src1_tag   = rs1_tag;
            dispatch_src1_value = 32'b0;
        end
    endcase
end

//
// Dispatch operand 2 lookup
//
always @(*) begin
    dispatch_src2_ready = 1'b0;
    dispatch_src2_tag   = rs2_tag;
    dispatch_src2_value = 32'b0;

    case (rs2_renamed)
        1'b0: begin
            dispatch_src2_ready = 1'b1;
            dispatch_src2_value = rs2_data;
        end

        1'b1: begin
            if (rob_lookup_valid2 && rob_lookup_ready2) begin
                dispatch_src2_ready = 1'b1;
                dispatch_src2_value = rob_lookup_value2;
            end else begin
                dispatch_src2_ready = 1'b0;
                dispatch_src2_tag   = rs2_tag;
            end
        end

        default: begin
            dispatch_src2_ready = 1'b0;
            dispatch_src2_tag   = rs2_tag;
            dispatch_src2_value = 32'b0;
        end
    endcase
end

endmodule
