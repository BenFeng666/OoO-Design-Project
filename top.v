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

// RAT outputs
wire        rs1_renamed;
wire [2:0]  rs1_tag;
wire        rs2_renamed;
wire [2:0]  rs2_tag;

// ROB wires
wire [2:0]  dispatch_rob_idx;
wire        rob_full;
wire        rob_empty;
wire        commit_valid;
wire [4:0]  commit_addr;
wire [31:0] commit_data;
wire        commit_reg_write;

// NOTE:
// This should really come from ROB at commit time.
// Add it to ROB later if your RAT needs exact matching to clear mappings safely.
wire [2:0]  commit_rob_idx;

// Issue Queue dispatch side
wire        dispatch_valid_iq;
wire [3:0]  dispatch_op;
wire        dispatch_src1_ready;
wire [2:0]  dispatch_src1_tag;
wire [31:0] dispatch_src1_value;
wire        dispatch_src2_ready;
wire [2:0]  dispatch_src2_tag;
wire [31:0] dispatch_src2_value;
wire [2:0]  dispatch_dest_tag;

// Issue Queue issue side
wire        issue_valid;
wire [3:0]  issue_op;
wire [31:0] issue_src1;
wire [31:0] issue_src2;
wire [2:0]  issue_dest_tag;
wire        iq_full;

// CDB wires
wire        cdb_valid;
wire [2:0]  cdb_tag;
wire [31:0] cdb_value;

// OoO ALU result
wire [31:0] ooo_alu_result;
wire        ooo_zero;
wire        ooo_negative;

//
// =========================
// Basic control / PC logic
// =========================
//
assign pc4           = pc + 32'd4;
assign branch_target = ex_pc + ex_imm;
assign jal_target    = ex_pc + ex_imm;

assign pc_sel = (ex_jump)            ? 2'b11 :
                (ex_Branch && zero)  ? 2'b01 :
                                       2'b00;

//
// =========================
// Temporary OoO dispatch logic
// =========================
//
assign dispatch_valid_iq   = ~rob_full & ~iq_full & WE;
assign dispatch_op         = alu_ctrl;
assign dispatch_dest_tag   = dispatch_rob_idx;

assign dispatch_src1_ready = ~rs1_renamed;
assign dispatch_src1_tag   = rs1_tag;
assign dispatch_src1_value = rs1_data;

assign dispatch_src2_ready = ~rs2_renamed;
assign dispatch_src2_tag   = rs2_tag;
assign dispatch_src2_value = rs2_data;

//
// =========================
// CDB from OoO ALU
// =========================
//
assign cdb_valid = issue_valid;
assign cdb_tag   = issue_dest_tag;
assign cdb_value = ooo_alu_result;

//
// =========================
// Temporary placeholder
// =========================
//
assign commit_rob_idx = cdb_tag;

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
ID_EX u_id_ex (
    .clk(clk),
    .rst(rst),
    .rs1(rs1_data),
    .rs2(rs2_data),
    .imm(imm),
    .ALUSrc(ALUSrc),
    .MemRead(MemRead),
    .MemWrite(MemWrite),
    .MemtoReg(MemtoReg),
    .Branch(Branch),
    .jump(jump),
    .ctrl(alu_ctrl),
    .rg_addr(id_instruction[11:7]),
    .rg_WE(WE),
    .ex_rs1(ex_rs1),
    .ex_rs2(ex_rs2),
    .ex_imm(ex_imm),
    .ex_ctrl(ex_ctrl),
    .ex_ALUSrc(ex_ALUSrc),
    .ex_MemRead(ex_MemRead),
    .ex_MemWrite(ex_MemWrite),
    .ex_MemtoReg(ex_MemtoReg),
    .ex_Branch(ex_Branch),
    .ex_rg_addr(ex_rg_addr),
    .ex_rg_WE(ex_rg_WE),
    .ex_jump(ex_jump),
    .pc(id_pc),
    .ex_pc(ex_pc)
);

ALU u_alu (
    .A(ex_rs1),
    .B(ex_ALUSrc ? ex_imm : ex_rs2),
    .ctrl(ex_ctrl),
    .result(alu_result),
    .zero(zero),
    .negative(negative)
);

ex_mem u_ex_mem (
    .clk(clk),
    .rst(rst),
    .zero(zero),
    .negative(negative),
    .alu_result(alu_result),
    .MemRead(ex_MemRead),
    .MemWrite(ex_MemWrite),
    .MemtoReg(ex_MemtoReg),
    .rg_WE(ex_rg_WE),
    .rg_addr(ex_rg_addr),
    .address(alu_result),
    .write_data(ex_rs2),
    .rs2(ex_rs2),
    .mem_rg_WE(mem_rg_WE),
    .mem_zero(mem_zero),
    .mem_negative(mem_negative),
    .mem_alu_result(mem_alu_result),
    .mem_MemRead(mem_MemRead),
    .mem_MemWrite(mem_MemWrite),
    .mem_MemtoReg(mem_MemtoReg),
    .mem_address(),
    .mem_rg_addr(mem_rg_addr),
    .mem_write_data(mem_write_data)
);

data_mem u_data_mem (
    .clk(clk),
    .rst(rst),
    .mem_read(mem_MemRead),
    .mem_write(mem_MemWrite),
    .address(mem_alu_result),
    .write_data(mem_write_data),
    .read_data(mem_data)
);

mem_wb u_mem_wb (
    .clk(clk),
    .rst(rst),
    .alu_result(mem_alu_result),
    .mem_data(mem_data),
    .MemtoReg(mem_MemtoReg),
    .reg_WE(mem_rg_WE),
    .rg_addr(mem_rg_addr),
    .wb_rg_WE(wb_rg_WE),
    .wb_rg_addr(wb_rg_addr),
    .wb_alu_result(wb_alu_result),
    .wb_mem_data(wb_mem_data),
    .wb_MemtoReg(wb_MemtoReg)
);

wb_mux u_wb_mux (
    .select(wb_MemtoReg),
    .alu_result(wb_alu_result),
    .mem_data(wb_mem_data),
    .wb_data(wb_data)
);

//
// =========================
// OoO modules
// =========================
//
RAT u_rat (
    .clk(clk),
    .rst(rst),
    .rs1(id_instruction[19:15]),
    .rs2(id_instruction[24:20]),
    .rd(id_instruction[11:7]),
    .rename_valid(dispatch_valid_iq),
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
    .dispatch_reg_write(WE),
    .dispatch_rob_idx(dispatch_rob_idx),
    .rob_full(rob_full),
    .rob_empty(rob_empty),
    .wb_valid(cdb_valid),
    .wb_rob_idx(cdb_tag),
    .wb_value(cdb_value),
    .commit_valid(commit_valid),
    .commit_addr(commit_addr),
    .commit_data(commit_data),
    .commit_reg_write(commit_reg_write)
    .commit_rob_idx(commit_rob_idx)
);

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
    .cdb_valid(cdb_valid),
    .cdb_tag(cdb_tag),
    .cdb_value(cdb_value),
    .iq_full(iq_full),
    .issue_valid(issue_valid),
    .issue_op(issue_op),
    .issue_src1(issue_src1),
    .issue_src2(issue_src2),
    .issue_dest_tag(issue_dest_tag)
);

ALU u_ooo_alu (
    .A(issue_src1),
    .B(issue_src2),
    .ctrl(issue_op),
    .result(ooo_alu_result),
    .zero(ooo_zero),
    .negative(ooo_negative)
);

endmodule
