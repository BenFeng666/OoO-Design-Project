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
// old pipeline wires (kept)
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

wire [31:0] alu_result;
wire        zero;
wire        negative;

wire        mem_zero;
wire        mem_negative;
wire [31:0] mem_alu_result;
wire        mem_MemRead;
wire        mem_MemWrite;
wire        mem_MemtoReg;
wire [31:0] mem_write_data;
wire [4:0]  mem_rg_addr;
wire        mem_rg_WE;

wire [31:0] mem_data;

wire        wb_rg_WE;
wire [4:0]  wb_rg_addr;
wire [31:0] wb_alu_result;
wire [31:0] wb_mem_data;
wire        wb_MemtoReg;

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
wire [2:0]  commit_rob_idx;

// Issue Queue dispatch side
wire        dispatch_valid_iq;
wire [3:0]  dispatch_op;
wire [2:0]  dispatch_dest_tag;
reg         dispatch_src1_ready;
reg  [2:0]  dispatch_src1_tag;
reg  [31:0] dispatch_src1_value;
reg         dispatch_src2_ready;
reg  [2:0]  dispatch_src2_tag;
reg  [31:0] dispatch_src2_value;

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

// ROB lookup wires
wire        rob_lookup_valid1;
wire        rob_lookup_ready1;
wire [31:0] rob_lookup_value1;
wire        rob_lookup_valid2;
wire        rob_lookup_ready2;
wire [31:0] rob_lookup_value2;

// OoO ALU result
wire [31:0] ooo_alu_result;
wire        ooo_zero;
wire        ooo_negative;

//
// =========================
// decode: supported OoO ops
// current backend supports only:
// add / sub / mul
// =========================
//
wire is_rtype;
wire is_add;
wire is_sub;
wire is_mul;
wire is_ooo_supported;

assign is_rtype = (id_instruction[6:0] == 7'b0110011);

assign is_add = is_rtype &&
                (id_instruction[14:12] == 3'b000) &&
                (id_instruction[31:25] == 7'b0000000);

assign is_sub = is_rtype &&
                (id_instruction[14:12] == 3'b000) &&
                (id_instruction[31:25] == 7'b0100000);

assign is_mul = is_rtype &&
                (id_instruction[14:12] == 3'b000) &&
                (id_instruction[31:25] == 7'b0000001);

assign is_ooo_supported = is_add || is_sub || is_mul;

//
// =========================
// Basic control / PC logic
// =========================
//
assign pc4           = pc + 32'd4;
assign branch_target = pc + imm;
assign jal_target    = pc + imm;

// branch path is not really supported yet in OoO backend,
// keep pc_sel simple for now
assign pc_sel = (jump) ? 2'b11 :
                2'b00;

//
// =========================
// OoO dispatch logic
// =========================
//
assign dispatch_valid_iq = is_ooo_supported && !rob_full && !iq_full;
assign dispatch_op       = alu_ctrl;
assign dispatch_dest_tag = dispatch_rob_idx;

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
// frontend
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
// commit writes back here
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
// OoO execute ALU
// =========================
//
ALU u_alu (
    .A(issue_src1),
    .B(issue_src2),
    .ctrl(issue_op),
    .result(ooo_alu_result),
    .zero(ooo_zero),
    .negative(ooo_negative)
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
    .dispatch_reg_write(dispatch_valid_iq),
    .dispatch_rob_idx(dispatch_rob_idx),
    .rob_full(rob_full),
    .rob_empty(rob_empty),

    .wb_valid(cdb_valid),
    .wb_rob_idx(cdb_tag),
    .wb_value(cdb_value),
    .commit_rob_idx(commit_rob_idx),

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
    .lookup_value2(rob_lookup_value2)
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
