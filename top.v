module top (
    input wire clk,
    input wire rst
);

//
// =========================
// IF stage wires
// =========================
//
wire [31:0] pc;
wire [31:0] next_pc;
wire [31:0] pc4;
wire [31:0] instruction;

//
// =========================
// IF/ID pipeline register wires
// =========================
//
wire [31:0] id_instruction;
wire [31:0] id_pc;
wire [31:0] id_pc4;

//
// =========================
// ID stage wires
// =========================
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
// =========================
// ID/EX pipeline register wires
// =========================
//
wire [31:0] ex_rs1;
wire [31:0] ex_rs2;
wire [31:0] ex_imm;
wire [3:0]  ex_ctrl;
wire        ex_ALUSrc;
wire        ex_MemRead;
wire        ex_MemWrite;
wire        ex_MemtoReg;
wire        ex_Branch;
wire        ex_jump;
wire [4:0]  ex_rg_addr;
wire        ex_rg_WE;
wire [31:0] ex_pc;

//
// =========================
// EX stage wires
// =========================
//
wire [31:0] alu_result;
wire        zero;
wire        negative;

//
// =========================
// EX/MEM pipeline register wires
// =========================
//
wire        mem_zero;
wire        mem_negative;
wire [31:0] mem_alu_result;
wire        mem_MemRead;
wire        mem_MemWrite;
wire        mem_MemtoReg;
wire [31:0] mem_write_data;
wire [4:0]  mem_rg_addr;
wire        mem_rg_WE;
wire [31:0] data_mem_addr;
wire [31:0] data_mem_wdata;
wire [31:0] data_mem_rdata;

assign data_mem_addr  = alu1_result;
assign data_mem_wdata = issue_src31;
//
// =========================
// MEM stage wires
// =========================
//
wire [31:0] mem_data;

//
// =========================
// MEM/WB pipeline register wires
// =========================
//
wire        wb_rg_WE;
wire [4:0]  wb_rg_addr;
wire [31:0] wb_alu_result;
wire [31:0] wb_mem_data;
wire        wb_MemtoReg;

//
// =========================
// WB stage wires
// =========================
//
wire [31:0] wb_data;

//
// =========================
// PC control wires
// =========================
//
wire [31:0] branch_target;
wire [31:0] jal_target;
wire [1:0]  pc_sel;

//
// =========================
// OoO wires
// =========================
//

// =========================
// RAT wires
// =========================
wire        rs1_renamed;
wire [2:0]  rs1_tag;
wire        rs2_renamed;
wire [2:0]  rs2_tag;

// =========================
// ROB wires
// =========================
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

// ROB lookup wires
wire        rob_lookup_valid1;
wire        rob_lookup_ready1;
wire [31:0] rob_lookup_value1;

wire        rob_lookup_valid2;
wire        rob_lookup_ready2;
wire [31:0] rob_lookup_value2;
wire [31:0] alu1_cdb_result;

wire [31:0] buffered_cdb_value;
wire [2:0]  buffered_cdb_tag;
wire        buffered_cdb_valid;
// =========================
// issue queue dispatch-side wires
// =========================
wire        dispatch_valid_iq;
wire [3:0]  dispatch_op;
wire [2:0]  dispatch_dest_tag;

reg         dispatch_src1_ready;
reg  [2:0]  dispatch_src1_tag;
reg  [31:0] dispatch_src1_value;

reg         dispatch_src2_ready;
reg  [2:0]  dispatch_src2_tag;
reg  [31:0] dispatch_src2_value;

// for full instruction support
wire        dispatch_use_imm;
wire        dispatch_reg_write;
wire        dispatch_mem_read;
wire        dispatch_mem_write;
wire        dispatch_branch;
wire        dispatch_jump;
wire        dispatch_jump_reg;
wire        imm_valid;

// =========================
// issue queue issue-side wires: slot 0
// =========================
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

// =========================
// issue queue issue-side wires: slot 1
// =========================
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

// =========================
// ALU0 result wires
// =========================
wire [31:0] alu0_result;
wire        alu0_zero;
wire        alu0_negative;

// =========================
// ALU1 result wires
// =========================
wire [31:0] alu1_result;
wire        alu1_zero;
wire        alu1_negative;

// =========================
// writeback / CDB wires
// =========================
// current issue_queue only has cdb_valid0/cdb_tag0/cdb_value0
wire        cdb_valid0;
wire [2:0]  cdb_tag0;
wire [31:0] cdb_value0;

// branch/store metadata going back to ROB
wire        wb_branch_taken;
wire [31:0] wb_target;
wire [31:0] wb_store_data;
//
// =========================
// Temporary placeholder
// =========================
//
//assign commit_rob_idx = cdb_tag;
assign dispatch_valid_iq  = !rob_full && !iq_full;
assign dispatch_op        = alu_ctrl;
assign dispatch_dest_tag  = dispatch_rob_idx;

assign dispatch_use_imm   = ALUSrc;
assign dispatch_reg_write = WE;
assign dispatch_mem_read  = MemRead;
assign dispatch_mem_write = MemWrite;
assign dispatch_branch    = Branch;
assign dispatch_jump      = jump;

// change this later if you distinguish jal and jalr
assign dispatch_jump_reg  = 1'b0;

assign imm_valid          = 1'b1;
assign cdb_value0 = buffered_cdb_value;
assign cdb_tag0   = buffered_cdb_tag;
assign cdb_valid0 = buffered_cdb_valid;

// placeholder until branch/store execute path is finished
assign wb_branch_taken = 1'b0;
assign wb_target       = 32'b0;
assign wb_store_data   = 32'b0;
assign alu1_cdb_result = issue_mem_read1 ? data_mem_rdata : alu1_result;
//
// =========================


// =========================
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
// =========================
// Architectural register file
// Commit writes back here
// =========================
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
// =========================
// Old in-order pipeline blocks
// Kept for now so frontend/control still exists
// =========================
//
// ID_EX u_id_ex (
//     .clk(clk),
//     .rst(rst),
//     .rs1(rs1_data),
//     .rs2(rs2_data),
//     .imm(imm),
//     .ALUSrc(ALUSrc),
//     .MemRead(MemRead),
//     .MemWrite(MemWrite),
//     .MemtoReg(MemtoReg),
//     .Branch(Branch),
//     .jump(jump),
//     .ctrl(alu_ctrl),
//     .rg_addr(id_instruction[11:7]),
//     .rg_WE(WE),
//     .ex_rs1(ex_rs1),
//     .ex_rs2(ex_rs2),
//     .ex_imm(ex_imm),
//     .ex_ctrl(ex_ctrl),
//     .ex_ALUSrc(ex_ALUSrc),
//     .ex_MemRead(ex_MemRead),
//     .ex_MemWrite(ex_MemWrite),
//     .ex_MemtoReg(ex_MemtoReg),
//     .ex_Branch(ex_Branch),
//     .ex_rg_addr(ex_rg_addr),
//     .ex_rg_WE(ex_rg_WE),
//     .ex_jump(ex_jump),
//     .pc(id_pc),
//     .ex_pc(ex_pc)
// );

// ALU u_alu (
//     .A(issue_src1),
//     .B(issue_src2),
//     .ctrl(issue_op),
//     .result(ooo_alu_result),
//     .zero(ooo_zero),
//     .negative(ooo_negative)
// );

// ex_mem u_ex_mem (
//     .clk(clk),
//     .rst(rst),
//     .zero(zero),
//     .negative(negative),
//     .alu_result(alu_result),
//     .MemRead(ex_MemRead),
//     .MemWrite(ex_MemWrite),
//     .MemtoReg(ex_MemtoReg),
//     .rg_WE(ex_rg_WE),
//     .rg_addr(ex_rg_addr),
//     .address(alu_result),
//     .write_data(ex_rs2),
//     .rs2(ex_rs2),
//     .mem_rg_WE(mem_rg_WE),
//     .mem_zero(mem_zero),
//     .mem_negative(mem_negative),
//     .mem_alu_result(mem_alu_result),
//     .mem_MemRead(mem_MemRead),
//     .mem_MemWrite(mem_MemWrite),
//     .mem_MemtoReg(mem_MemtoReg),
//     .mem_address(),
//     .mem_rg_addr(mem_rg_addr),
//     .mem_write_data(mem_write_data)
// );

data_mem u_data_mem (
    .clk(clk),
    .rst(rst),
    .mem_read(issue_valid1 && issue_mem_read1),
    .mem_write(issue_valid1 && issue_mem_write1),
    .address(data_mem_addr),
    .write_data(data_mem_wdata),
    .read_data(data_mem_rdata)
);

// mem_wb u_mem_wb (
//     .clk(clk),
//     .rst(rst),
//     .alu_result(mem_alu_result),
//     .mem_data(mem_data),
//     .MemtoReg(mem_MemtoReg),
//     .reg_WE(mem_rg_WE),
//     .rg_addr(mem_rg_addr),
//     .wb_rg_WE(wb_rg_WE),
//     .wb_rg_addr(wb_rg_addr),
//     .wb_alu_result(wb_alu_result),
//     .wb_mem_data(wb_mem_data),
//     .wb_MemtoReg(wb_MemtoReg)
// );

// wb_mux u_wb_mux (
//     .select(wb_MemtoReg),
//     .alu_result(wb_alu_result),
//     .mem_data(wb_mem_data),
//     .wb_data(wb_data)
// );

//
// =========================
// OoO modules
// =========================
//
CDB_buffer u_cdb_buffer (
    .clk(clk),
    .rst(rst),

    .ALU0_result(alu0_result),
    .ALU0_tag(issue_dest_tag0),
    .ALU0_valid(issue_valid0),

    .ALU1_result(alu1_cdb_result),
    .ALU1_tag(issue_dest_tag1),
    .ALU1_valid(issue_valid1),

    .cdb_value(buffered_cdb_value),
    .cdb_tag(buffered_cdb_tag),
    .cdb_valid(buffered_cdb_valid)
);

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

issue_queue u_issue_queue (
    .clk(clk),
    .rst(rst),
    // dispatch side
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

    // issue slot 0
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

    // issue slot 1
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
    .issue_dest_tag1(issue_dest_tag1)
); 

ALU0 u_alu0 (
    .A(issue_src10),
    .B(issue_use_imm0 ? issue_imm0 : issue_src20),
    .ctrl(issue_alu_op0),
    .result(alu0_result),
    .zero(alu0_zero),
    .negative(alu0_negative)
);

ALU1 u_alu1 (
    .A(issue_src11),
    .B(issue_use_imm1 ? issue_imm1 : issue_src21),
    .ctrl(issue_alu_op1),
    .result(alu1_result),
    .zero(alu1_zero),
    .negative(alu1_negative)
);


always @(*) begin
    // defaults
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
            end
            else begin
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

always @(*) begin
    // defaults
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
            end
            else begin
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
