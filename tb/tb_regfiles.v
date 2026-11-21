// =============================================================================
// tb_regfiles.v - tests the vector and scalar register files
// =============================================================================
// What we check:
//   Vector register file (8 registers x 128 bits), normal version (BYPASS = 0)
//     * every register can be written and read back through BOTH read ports
//     * nothing is written when write_en = 0
//     * only the lanes switched on in write_lanes change
//     * reading a register while writing it gives the old value until the
//       clock edge, then the new value
//     * the lane mask starts with every lane on and can be changed
//     * 2000 random reads/writes (random lanes too) match a simple copy kept
//       by the testbench
//   Vector register file, write-through version (BYPASS = 1)
//     * a read of the register being written already shows the new value,
//       but only in the lanes being written; other registers are unaffected
//     * the mask shows a new value in the same cycle it is written
//     * 2000 random cycles: before every clock edge the read ports must show
//       exactly "the stored value with this cycle's write laid on top"
//   Scalar register file (8 registers x 32 bits), both versions
//     * s0 always reads 0, even after we try to write it (and even through
//       the bypass)
//     * s1..s7 write and read back, debug port shows the same values
//     * 2000 random reads/writes match the testbench copy, for each version
//
// Run:  make tb_regfiles
// =============================================================================

`timescale 1ns/1ps

module tb_regfiles;

    localparam LANES = 8;
    localparam W     = 16;
    localparam VLEN  = LANES * W;
    localparam ALL   = {LANES{1'b1}};      // every lane on

    reg clk = 1'b0;
    always #5 clk = ~clk;        // 10 ns clock period

    integer errors = 0;
    integer checks = 0;
    integer seed   = 7;
    integer i, r, k;

    // ---- Vector register files: one normal, one write-through -------------------
    // Both get exactly the same inputs, so they must always hold the same
    // values; only what they show DURING a write may differ.
    reg  [2:0]       v_ra, v_rb, v_wa;
    reg              v_we, m_we;
    reg  [LANES-1:0] v_lanes, m_wd;
    reg  [VLEN-1:0]  v_wd;
    wire [VLEN-1:0]  v_qa, v_qb, p_qa, p_qb;
    wire [LANES-1:0] v_mask, p_mask;

    vec_regfile #(.LANES(LANES), .W(W), .BYPASS(0)) u_vrf (
        .clk(clk),
        .read_addr_a(v_ra), .read_data_a(v_qa),
        .read_addr_b(v_rb), .read_data_b(v_qb),
        .write_en(v_we), .write_lanes(v_lanes), .write_addr(v_wa), .write_data(v_wd),
        .mask(v_mask), .mask_write_en(m_we), .mask_write_data(m_wd)
    );

    vec_regfile #(.LANES(LANES), .W(W), .BYPASS(1)) u_vbp (
        .clk(clk),
        .read_addr_a(v_ra), .read_data_a(p_qa),
        .read_addr_b(v_rb), .read_data_b(p_qb),
        .write_en(v_we), .write_lanes(v_lanes), .write_addr(v_wa), .write_data(v_wd),
        .mask(p_mask), .mask_write_en(m_we), .mask_write_data(m_wd)
    );

    // ---- Scalar register files: one normal, one write-through -------------------
    reg  [2:0]  s_ra, s_rb, s_wa, s_dbg;
    reg         s_we;
    reg  [31:0] s_wd;
    wire [31:0] s_qa, s_qb, s_qdbg, t_qa, t_qb, t_qdbg;

    scalar_regfile #(.BYPASS(0)) u_srf (
        .clk(clk),
        .read_addr_a(s_ra), .read_data_a(s_qa),
        .read_addr_b(s_rb), .read_data_b(s_qb),
        .write_en(s_we), .write_addr(s_wa), .write_data(s_wd),
        .debug_addr(s_dbg), .debug_data(s_qdbg)
    );

    scalar_regfile #(.BYPASS(1)) u_sbp (
        .clk(clk),
        .read_addr_a(s_ra), .read_data_a(t_qa),
        .read_addr_b(s_rb), .read_data_b(t_qb),
        .write_en(s_we), .write_addr(s_wa), .write_data(s_wd),
        .debug_addr(s_dbg), .debug_data(t_qdbg)
    );

    // Our own copies of what the registers should hold.
    reg [VLEN-1:0]  v_model [0:7];
    reg [LANES-1:0] m_model;
    reg [31:0]      s_model [0:7];

    // Compare a value with the expected one and count errors.
    task expect_eq;
        input [VLEN-1:0] got, want;
        input [8*24-1:0] what;
        begin
            checks = checks + 1;
            if (got !== want) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("  MISMATCH %0s: got %h want %h", what, got, want);
            end
        end
    endtask

    // A different 128-bit pattern for each register number.
    function [VLEN-1:0] pattern;
        input [2:0] n;
        pattern = {LANES{8'hA0 + n, 8'h10 * n + 8'h05}};
    endfunction

    // "old" with the lanes chosen by "lanes" replaced by "new_value": what a
    // register holds after a write that only changes some lanes.
    function [VLEN-1:0] merge;
        input [VLEN-1:0]  old, new_value;
        input [LANES-1:0] lanes;
        integer n;
        begin
            merge = old;
            for (n = 0; n < LANES; n = n + 1)
                if (lanes[n]) merge[n*W +: W] = new_value[n*W +: W];
        end
    endfunction

    // What the write-through file should show on a read port right now.
    function [VLEN-1:0] bypass_view;
        input [2:0] addr;
        begin
            if (v_we && v_wa == addr) bypass_view = merge(v_model[addr], v_wd, v_lanes);
            else                      bypass_view = v_model[addr];
        end
    endfunction

    initial begin
        v_we = 0; v_lanes = ALL; m_we = 0; m_wd = 0;
        s_we = 0;
        v_ra = 0; v_rb = 0; v_wa = 0; v_wd = 0;
        s_ra = 0; s_rb = 0; s_wa = 0; s_wd = 0; s_dbg = 0;
        $display("tb_regfiles: vector %0d x %0d bits, scalar 8 x 32 bits", 8, VLEN);

        // ================= Vector register file =================

        // 1. Write a unique pattern into every register.
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            v_we = 1; v_wa = i; v_wd = pattern(i);
            v_model[i] = pattern(i);
        end
        @(negedge clk) v_we = 0;

        // 2. Read every register back through port A and port B, on both files.
        //    Port B reads in reverse order so both ports move independently.
        for (i = 0; i < 8; i = i + 1) begin
            v_ra = i; v_rb = 7 - i; #1;
            expect_eq(v_qa, v_model[i],     "vreg port A");
            expect_eq(v_qb, v_model[7 - i], "vreg port B");
            expect_eq(p_qa, v_model[i],     "write-through port A");
            expect_eq(p_qb, v_model[7 - i], "write-through port B");
        end

        // 3. write_en = 0 must not change anything (and must not bypass).
        @(negedge clk);
        v_we = 0; v_wa = 3; v_wd = {VLEN{1'b1}}; v_ra = 3; #1;
        expect_eq(p_qa, v_model[3], "write-through, write off");
        @(negedge clk);
        expect_eq(v_qa, v_model[3], "vreg write_en=0");

        // 4. Only the lanes switched on may change: lanes 0 and 2 here.
        @(negedge clk);
        v_we = 1; v_wa = 4; v_wd = {LANES{16'h1234}}; v_lanes = 8'b0000_0101;
        @(negedge clk);
        v_we = 0; v_lanes = ALL;
        v_model[4] = merge(v_model[4], {LANES{16'h1234}}, 8'b0000_0101);
        v_ra = 4; #1;
        expect_eq(v_qa, v_model[4], "vreg lanes 0 and 2 only");
        expect_eq(p_qa, v_model[4], "write-through lanes 0 and 2");

        // 5. Read while writing the same register.
        //    Normal file: old value before the edge, new value after it.
        //    Write-through file: the new value at once, in the written lanes only
        //    (lanes 1 and 7 here); a different register shows no change.
        @(negedge clk);
        v_we = 1; v_wa = 5; v_wd = {LANES{16'hBEEF}}; v_lanes = 8'b1000_0010;
        v_ra = 5; v_rb = 6; #1;
        expect_eq(v_qa, v_model[5], "vreg read-before-edge");
        expect_eq(p_qa, merge(v_model[5], {LANES{16'hBEEF}}, 8'b1000_0010), "write-through same cycle");
        expect_eq(p_qb, v_model[6], "write-through other reg");
        @(posedge clk); #1;
        v_model[5] = merge(v_model[5], {LANES{16'hBEEF}}, 8'b1000_0010);
        expect_eq(v_qa, v_model[5], "vreg read-after-edge");
        expect_eq(p_qa, v_model[5], "write-through after edge");
        @(negedge clk) begin v_we = 0; v_lanes = ALL; end

        // 6. The lane mask: every lane on at power-up, then changed.
        #1;
        expect_eq(v_mask, ALL, "mask starts all on");
        expect_eq(p_mask, ALL, "write-through mask start");
        @(negedge clk);
        m_we = 1; m_wd = 8'b0110_1001; #1;
        expect_eq(v_mask, ALL,          "mask before edge");      // old value until the edge
        expect_eq(p_mask, 8'b0110_1001, "write-through mask now"); // new value straight away
        @(negedge clk);
        m_we = 0; m_wd = 8'b1111_0000; #1;                       // write off: no change
        expect_eq(v_mask, 8'b0110_1001, "mask after edge");
        expect_eq(p_mask, 8'b0110_1001, "write-through mask held");
        m_model = 8'b0110_1001;

        // 7. Random writes (random lanes and random mask writes) and reads.
        //    Before each edge: the normal file shows the stored copy, the
        //    write-through file shows the stored copy with this write on top.
        for (r = 0; r < 2000; r = r + 1) begin
            @(negedge clk);
            v_we    = $random(seed);
            v_wa    = $random(seed);
            v_wd    = {$random(seed), $random(seed), $random(seed), $random(seed)};
            v_lanes = (r % 4 == 0) ? ALL : $random(seed);
            v_ra    = (r % 3 == 0) ? v_wa : $random(seed);    // often read what is being written
            v_rb    = $random(seed);
            m_we    = (r % 5 == 0);
            m_wd    = $random(seed);
            #1;
            expect_eq(v_qa,   v_model[v_ra],      "vreg random A");
            expect_eq(v_qb,   v_model[v_rb],      "vreg random B");
            expect_eq(p_qa,   bypass_view(v_ra),  "write-through random A");
            expect_eq(p_qb,   bypass_view(v_rb),  "write-through random B");
            expect_eq(v_mask, m_model,            "mask random");
            expect_eq(p_mask, m_we ? m_wd : m_model, "write-through mask random");
            @(posedge clk);
            if (v_we) v_model[v_wa] = merge(v_model[v_wa], v_wd, v_lanes);
            if (m_we) m_model = m_wd;
        end
        @(negedge clk) begin v_we = 0; m_we = 0; end

        // ================= Scalar register file =================

        for (i = 0; i < 8; i = i + 1) s_model[i] = 0;

        // 8. Write s0..s7 (including s0, which must ignore the write).
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            s_we = 1; s_wa = i; s_wd = 32'h1000_0000 * (i + 1) + i;
            if (i != 0) s_model[i] = s_wd;
        end
        @(negedge clk) s_we = 0;

        // 9. Read back through A, B and the debug port, on both files. s0 must be 0.
        for (i = 0; i < 8; i = i + 1) begin
            s_ra = i; s_rb = 7 - i; s_dbg = i; #1;
            expect_eq(s_qa,   s_model[i],     "sreg port A");
            expect_eq(s_qb,   s_model[7 - i], "sreg port B");
            expect_eq(s_qdbg, s_model[i],     "sreg debug port");
            expect_eq(t_qa,   s_model[i],     "s write-through A");
            expect_eq(t_qb,   s_model[7 - i], "s write-through B");
        end
        s_ra = 0; #1;
        expect_eq(s_qa, 32'd0, "s0 hard-wired zero");

        // 10. Write-through: the new value shows at once; s0 never bypasses.
        @(negedge clk);
        s_we = 1; s_wa = 3; s_wd = 32'hCAFE_F00D; s_ra = 3; s_rb = 4; #1;
        expect_eq(s_qa, s_model[3],   "sreg read-before-edge");
        expect_eq(t_qa, 32'hCAFE_F00D, "s write-through same cycle");
        expect_eq(t_qb, s_model[4],    "s write-through other reg");
        @(negedge clk);
        s_model[3] = 32'hCAFE_F00D;
        s_wa = 0; s_wd = 32'h1111_2222; s_ra = 0; #1;
        expect_eq(t_qa, 32'd0, "s0 write-through stays 0");
        @(negedge clk) s_we = 0;

        // 11. Random writes and reads, on both files.
        for (r = 0; r < 2000; r = r + 1) begin
            @(negedge clk);
            s_we  = $random(seed);
            s_wa  = $random(seed);
            s_wd  = $random(seed);
            s_ra  = (r % 3 == 0) ? s_wa : $random(seed);
            s_rb  = $random(seed);
            s_dbg = $random(seed);
            #1;
            expect_eq(s_qa,   s_model[s_ra],  "sreg random A");
            expect_eq(s_qb,   s_model[s_rb],  "sreg random B");
            expect_eq(s_qdbg, s_model[s_dbg], "sreg random debug");
            expect_eq(t_qa, (s_we && s_wa == s_ra && s_ra != 0) ? s_wd : s_model[s_ra], "s write-through random A");
            expect_eq(t_qb, (s_we && s_wa == s_rb && s_rb != 0) ? s_wd : s_model[s_rb], "s write-through random B");
            expect_eq(t_qdbg, s_model[s_dbg], "s write-through debug");
            @(posedge clk);
            if (s_we && s_wa != 0) s_model[s_wa] = s_wd;
        end

        $display("tb_regfiles: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED");
        $finish;
    end

endmodule
