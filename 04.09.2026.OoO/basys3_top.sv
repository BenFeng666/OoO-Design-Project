`timescale 1ns / 1ps

// ============================================================================
// basys3_top.sv — Minimal Basys 3 wrapper for the educational OoO RV32I core
// ============================================================================
// First FPGA demo goals:
//   - keep the already-working CPU core unchanged
//   - slow the CPU clock down to a human-visible rate
//   - show basic status on LEDs
//   - show last committed PC or last committed value on the 4-digit 7-seg
//
// Board interface choices:
//   - CLK100MHZ : Basys 3 100 MHz oscillator
//   - btnC      : active-high reset button
//   - sw[0]     : display source select
//                  0 = last committed PC
//                  1 = last committed value
//   - sw[1]     : 16-bit half select
//                  0 = low  16 bits
//                  1 = high 16 bits
//   - led[0]    : heartbeat (1 Hz blink)
//   - led[1]    : CPU halt observed
//   - led[2]    : commit pulse (stretched for visibility)
//   - led[3]    : fetch_valid
//   - led[4]    : dispatch_valid
//   - led[5]    : issue_valid
//   - led[6]    : execute_valid / CDB valid
//   - led[7]    : commit_valid (raw)
//   - led[15:8] : zero
//
// Notes:
//   - This wrapper uses a simple divided fabric clock for the CPU because the
//     immediate goal is a clean first bring-up on Basys 3.
//   - For a more production-style FPGA design later, prefer a clock-enable
//     architecture or a dedicated clock-management / buffering approach.
// ============================================================================

module basys3_top #(
    parameter int ROM_DEPTH = 256,
    parameter int ROB_DEPTH = 4,
    parameter int RS_DEPTH  = 4,
    parameter     MEM_FILE  = "program.hex",

    // 100 MHz / (2 * 12_500_000) = 4 Hz CPU clock
    parameter int CPU_HALF_PERIOD_CLKS = 12_500_000,

    // 100 MHz / (2 * 50_000_000) = 1 Hz heartbeat blink
    parameter int HEARTBEAT_HALF_PERIOD_CLKS = 50_000_000
)(
    input  logic        CLK100MHZ,
    input  logic        btnC,
    input  logic [1:0]  sw,

    output logic [15:0] led,
    output logic [6:0]  seg,
    output logic        dp,
    output logic [3:0]  an
);

    // ------------------------------------------------------------------------
    // Slow CPU clock generation
    // ------------------------------------------------------------------------
    logic [$clog2(CPU_HALF_PERIOD_CLKS)-1:0] cpu_div_cnt = '0;
    logic                                     cpu_clk     = 1'b0;

    always_ff @(posedge CLK100MHZ) begin
        if (btnC) begin
            cpu_div_cnt <= '0;
            cpu_clk     <= 1'b0;
        end else begin
            if (cpu_div_cnt == CPU_HALF_PERIOD_CLKS-1) begin
                cpu_div_cnt <= '0;
                cpu_clk     <= ~cpu_clk;
            end else begin
                cpu_div_cnt <= cpu_div_cnt + 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Simple power-on reset stretcher + button reset
    // Core reset is active-low.
    // ------------------------------------------------------------------------
    localparam int POR_CLKS = 1024;
    logic [$clog2(POR_CLKS)-1:0] por_cnt    = '0;
    logic                        por_active = 1'b1;
    logic                        cpu_rst_n;

    always_ff @(posedge CLK100MHZ) begin
        if (btnC) begin
            por_cnt    <= '0;
            por_active <= 1'b1;
        end else if (por_active) begin
            if (por_cnt == POR_CLKS-1) begin
                por_active <= 1'b0;
            end else begin
                por_cnt <= por_cnt + 1'b1;
            end
        end
    end

    assign cpu_rst_n = ~(btnC | por_active);

    // ------------------------------------------------------------------------
    // CPU core debug signals
    // ------------------------------------------------------------------------
    logic [31:0] dbg_pc;
    logic        dbg_fetch_valid;
    logic        dbg_decode_valid;
    logic        dbg_dispatch_valid;
    logic        dbg_issue_valid;
    logic        dbg_execute_valid;
    logic        dbg_commit_valid;
    logic [31:0] dbg_commit_pc;
    logic [4:0]  dbg_commit_rd;
    logic [31:0] dbg_commit_value;
    logic        dbg_commit_uses_rd;
    logic        dbg_halt;

    ooo_cpu_core #(
        .ROM_DEPTH (ROM_DEPTH),
        .ROB_DEPTH (ROB_DEPTH),
        .RS_DEPTH  (RS_DEPTH),
        .MEM_FILE  (MEM_FILE)
    ) u_core (
        .clk               (cpu_clk),
        .rst_n             (cpu_rst_n),
        .dbg_pc            (dbg_pc),
        .dbg_fetch_valid   (dbg_fetch_valid),
        .dbg_decode_valid  (dbg_decode_valid),
        .dbg_dispatch_valid(dbg_dispatch_valid),
        .dbg_issue_valid   (dbg_issue_valid),
        .dbg_execute_valid (dbg_execute_valid),
        .dbg_commit_valid  (dbg_commit_valid),
        .dbg_commit_pc     (dbg_commit_pc),
        .dbg_commit_rd     (dbg_commit_rd),
        .dbg_commit_value  (dbg_commit_value),
        .dbg_commit_uses_rd(dbg_commit_uses_rd),
        .dbg_halt          (dbg_halt)
    );

    // ------------------------------------------------------------------------
    // Latch last committed architectural information in the CPU clock domain.
    // This makes the demo much easier to read on the seven-segment display.
    // ------------------------------------------------------------------------
    logic [31:0] last_commit_pc      = 32'h0000_0000;
    logic [31:0] last_commit_value   = 32'h0000_0000;
    logic [4:0]  last_commit_rd      = 5'd0;
    logic        last_commit_uses_rd = 1'b0;

    always_ff @(posedge cpu_clk) begin
        if (!cpu_rst_n) begin
            last_commit_pc      <= 32'h0000_0000;
            last_commit_value   <= 32'h0000_0000;
            last_commit_rd      <= 5'd0;
            last_commit_uses_rd <= 1'b0;
        end else if (dbg_commit_valid) begin
            last_commit_pc      <= dbg_commit_pc;
            last_commit_rd      <= dbg_commit_rd;
            last_commit_uses_rd <= dbg_commit_uses_rd;

            if (dbg_commit_uses_rd)
                last_commit_value <= dbg_commit_value;
        end
    end

    // ------------------------------------------------------------------------
    // Heartbeat in the 100 MHz domain
    // ------------------------------------------------------------------------
    logic [$clog2(HEARTBEAT_HALF_PERIOD_CLKS)-1:0] heartbeat_cnt = '0;
    logic                                          heartbeat     = 1'b0;

    always_ff @(posedge CLK100MHZ) begin
        if (btnC) begin
            heartbeat_cnt <= '0;
            heartbeat     <= 1'b0;
        end else begin
            if (heartbeat_cnt == HEARTBEAT_HALF_PERIOD_CLKS-1) begin
                heartbeat_cnt <= '0;
                heartbeat     <= ~heartbeat;
            end else begin
                heartbeat_cnt <= heartbeat_cnt + 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Synchronize a few single-bit slow-domain debug signals into the 100 MHz
    // display/LED domain.
    // ------------------------------------------------------------------------
    logic halt_meta   = 1'b0, halt_sync   = 1'b0;
    logic fetch_meta  = 1'b0, fetch_sync  = 1'b0;
    logic disp_meta   = 1'b0, disp_sync   = 1'b0;
    logic issue_meta  = 1'b0, issue_sync  = 1'b0;
    logic exec_meta   = 1'b0, exec_sync   = 1'b0;
    logic commit_meta = 1'b0, commit_sync = 1'b0;
    logic commit_sync_d = 1'b0;

    always_ff @(posedge CLK100MHZ) begin
        halt_meta   <= dbg_halt;
        halt_sync   <= halt_meta;

        fetch_meta  <= dbg_fetch_valid;
        fetch_sync  <= fetch_meta;

        disp_meta   <= dbg_dispatch_valid;
        disp_sync   <= disp_meta;

        issue_meta  <= dbg_issue_valid;
        issue_sync  <= issue_meta;

        exec_meta   <= dbg_execute_valid;
        exec_sync   <= exec_meta;

        commit_meta <= dbg_commit_valid;
        commit_sync <= commit_meta;
        commit_sync_d <= commit_sync;
    end

    wire commit_rise = commit_sync & ~commit_sync_d;

    // ------------------------------------------------------------------------
    // Stretch commit LED pulse so it is visible even if you later speed up the
    // CPU clock.
    // ------------------------------------------------------------------------
    localparam int COMMIT_LED_STRETCH_CLKS = 25_000_000; // 0.25 s at 100 MHz
    logic [$clog2(COMMIT_LED_STRETCH_CLKS)-1:0] commit_led_cnt = '0;
    logic                                       commit_led_on  = 1'b0;

    always_ff @(posedge CLK100MHZ) begin
        if (btnC) begin
            commit_led_cnt <= '0;
            commit_led_on  <= 1'b0;
        end else if (commit_rise) begin
            commit_led_cnt <= COMMIT_LED_STRETCH_CLKS-1;
            commit_led_on  <= 1'b1;
        end else if (commit_led_on) begin
            if (commit_led_cnt == 0) begin
                commit_led_on <= 1'b0;
            end else begin
                commit_led_cnt <= commit_led_cnt - 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------------
    // LEDs
    // ------------------------------------------------------------------------
    always_comb begin
        led       = 16'h0000;
        led[0]    = heartbeat;
        led[1]    = halt_sync;
        led[2]    = commit_led_on;
        led[3]    = fetch_sync;
        led[4]    = disp_sync;
        led[5]    = issue_sync;
        led[6]    = exec_sync;
        led[7]    = commit_sync;
        // led[15:8] remain 0
    end

    // ------------------------------------------------------------------------
    // 7-segment display selection
    // sw[0] = 0 -> last committed PC
    // sw[0] = 1 -> last committed value
    // sw[1] = 0 -> low 16 bits
    // sw[1] = 1 -> high 16 bits
    // ------------------------------------------------------------------------
    logic [31:0] display_word;
    logic [15:0] display_halfword;

    always_comb begin
        display_word = (sw[0] == 1'b0) ? last_commit_pc : last_commit_value;
        display_halfword = (sw[1] == 1'b0) ? display_word[15:0]
                                           : display_word[31:16];
    end

    // ------------------------------------------------------------------------
    // Hex digit extraction
    // ------------------------------------------------------------------------
    logic [3:0] hex3, hex2, hex1, hex0;
    assign hex3 = display_halfword[15:12];
    assign hex2 = display_halfword[11:8];
    assign hex1 = display_halfword[7:4];
    assign hex0 = display_halfword[3:0];

    // ------------------------------------------------------------------------
    // 7-segment multiplex refresh (~763 Hz digit-scan with refresh_cnt[15:14])
    // Active-low segments and active-low anodes on Basys 3.
    // ------------------------------------------------------------------------
    logic [15:0] refresh_cnt = 16'd0;
    logic [1:0]  digit_sel;
    logic [3:0]  current_hex;

    always_ff @(posedge CLK100MHZ) begin
        if (btnC)
            refresh_cnt <= 16'd0;
        else
            refresh_cnt <= refresh_cnt + 16'd1;
    end

    assign digit_sel = refresh_cnt[15:14];

    always_comb begin
        an = 4'b1111;
        current_hex = 4'h0;

        case (digit_sel)
            2'b00: begin
                an = 4'b1110;   // rightmost digit
                current_hex = hex0;
            end
            2'b01: begin
                an = 4'b1101;
                current_hex = hex1;
            end
            2'b10: begin
                an = 4'b1011;
                current_hex = hex2;
            end
            2'b11: begin
                an = 4'b0111;   // leftmost digit
                current_hex = hex3;
            end
            default: begin
                an = 4'b1111;
                current_hex = 4'h0;
            end
        endcase
    end

    always_comb begin
        case (current_hex)
            4'h0: seg = 7'b1000000;
            4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;
            4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;
            4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;
            4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;
            4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000;
            4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110;
            4'hD: seg = 7'b0100001;
            4'hE: seg = 7'b0000110;
            4'hF: seg = 7'b0001110;
            default: seg = 7'b1111111;
        endcase
    end

    assign dp = 1'b1; // decimal point off (active-low)

endmodule
