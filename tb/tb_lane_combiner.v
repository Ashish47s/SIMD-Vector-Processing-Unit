// =============================================================================
// tb_lane_combiner.v - tests the lane mux and the result combiner
// =============================================================================
// What we check:
//   Lane mux
//     * use_scalar = 0: every lane passes its own vector element through
//     * use_scalar = 1: every lane receives the same scalar value
//
//   Result combiner (original behaviour)
//     * vector_result is exactly the lane inputs (always all lanes)
//     * sum_result equals the lanes added one by one with ALL lanes enabled
//       (checks the adder TREE against a plain chain)
//     * extreme cases: largest / smallest / -1 / 0
//     * 5000 random vectors
//
//   Masked lane sums (new: lane_enable)
//     * All lanes enabled
//     * All lanes disabled  -> sum must be 0
//     * Only lane 0 enabled
//     * Only the last lane enabled
//     * Each lane enabled individually
//     * Alternating patterns (0101... and 1010...)
//     * 500 random enable masks with random data
//     * Positive, negative and zero values under random masks
//     * Maximum positive (0x7FFF) and minimum negative (0x8000) under masks
//     * vector_result must be unchanged regardless of lane_enable
//
//   Lane flags (new: lane_flags)
//     * Flag 0 when lane result is zero
//     * Flag 1 when lane result is positive
//     * Flag 1 when lane result is negative (non-zero signed)
//     * Flag independence from lane_enable: a disabled lane still raises its
//       flag if its result is non-zero
//     * Individual lane flag correctness verified for every lane
//     * 1000 random result / enable combinations
//
// LANES is a parameter; the Makefile runs this test for 1, 2, 4 and 8 lanes.
//
// Self-checking: prints total check count and error count, and prints
// TEST PASSED only if every check succeeds.
//
// Run:  make tb_lane_combiner
// =============================================================================

`timescale 1ns/1ps

module tb_lane_combiner;

    parameter LANES = 8;
    localparam W = 16;

    integer errors = 0;
    integer checks = 0;
    integer seed   = 42;      // reproducible but different from the original
    integer r, j;

    // ---- Lane mux --------------------------------------------------------------
    reg                use_scalar;
    reg  [LANES*W-1:0] vector_b;
    reg  [W-1:0]       scalar_b;
    wire [LANES*W-1:0] lane_b;

    lane_mux #(.LANES(LANES), .W(W)) u_mux (
        .use_scalar(use_scalar), .vector_b(vector_b),
        .scalar_b(scalar_b), .lane_b(lane_b)
    );

    // ---- Result combiner -------------------------------------------------------
    reg  [LANES*W-1:0] lanes_in;
    reg  [LANES-1:0]   lane_en;      // the new enable input
    wire [LANES*W-1:0] vector_result;
    wire [31:0]        sum_result;
    wire [LANES-1:0]   lane_flags;   // the new flags output

    result_combiner #(.LANES(LANES), .W(W)) u_comb (
        .lane_results  (lanes_in),
        .lane_enable   (lane_en),
        .vector_result (vector_result),
        .sum_result    (sum_result),
        .lane_flags    (lane_flags)
    );

    // -------------------------------------------------------------------------
    // Reference model: compute the masked sum independently (plain loop).
    // -------------------------------------------------------------------------
    function [31:0] masked_sum;
        input [LANES*W-1:0] v;
        input [LANES-1:0]   en;
        integer n;
        reg signed [31:0] total;
        begin
            total = 0;
            for (n = 0; n < LANES; n = n + 1)
                if (en[n])
                    total = total + $signed(v[n*W +: W]);
            masked_sum = total;
        end
    endfunction

    // Reference model: expected flags (independent of lane_enable).
    function [LANES-1:0] expected_flags;
        input [LANES*W-1:0] v;
        integer n;
        reg [LANES-1:0] f;
        begin
            f = {LANES{1'b0}};
            for (n = 0; n < LANES; n = n + 1)
                if (v[n*W +: W] != {W{1'b0}})
                    f[n] = 1'b1;
            expected_flags = f;
        end
    endfunction

    // -------------------------------------------------------------------------
    // Check helpers
    // -------------------------------------------------------------------------
    // Generic: compare two LANES*W-bit values.
    task check_vec;
        input [LANES*W-1:0] got, want;
        input [8*32-1:0]    what;
        begin
            checks = checks + 1;
            if (got !== want) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("  MISMATCH %0s: got %h  want %h", what, got, want);
            end
        end
    endtask

    // Compare a 32-bit sum result.
    task check_sum;
        input [31:0] got, want;
        input [8*32-1:0] what;
        begin
            checks = checks + 1;
            if (got !== want) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("  MISMATCH %0s: got %h  want %h", what, got, want);
            end
        end
    endtask

    // Compare a LANES-bit flag vector.
    task check_flags;
        input [LANES-1:0] got, want;
        input [8*32-1:0]  what;
        begin
            checks = checks + 1;
            if (got !== want) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("  MISMATCH %0s: got %b  want %b", what, got, want);
            end
        end
    endtask

    // Run one full combiner check: sum, vector_result and flags.
    task check_combiner;
        begin
            #1;
            // vector_result must always be the raw lane data.
            check_vec(vector_result, lanes_in,          "vector_result");
            // sum must match the reference masked sum.
            check_sum(sum_result, masked_sum(lanes_in, lane_en), "sum_result");
            // flags must match the reference (independent of enable).
            check_flags(lane_flags, expected_flags(lanes_in), "lane_flags");
        end
    endtask

    // -------------------------------------------------------------------------
    // Test body
    // -------------------------------------------------------------------------
    initial begin
        $display("tb_lane_combiner: %0d lanes x %0d bits", LANES, W);

        // =====================================================================
        // A. Lane mux: 1000 random cases in both modes
        // =====================================================================
        for (r = 0; r < 1000; r = r + 1) begin
            for (j = 0; j < LANES; j = j + 1)
                vector_b[j*W +: W] = $random(seed);
            scalar_b   = $random(seed);
            use_scalar = r[0];
            #1;
            if (use_scalar) check_vec(lane_b, {LANES{scalar_b}}, "mux broadcast");
            else            check_vec(lane_b, vector_b,          "mux vector");
        end

        // =====================================================================
        // B. Original combiner behaviour: ALL lanes enabled, extreme values
        // =====================================================================
        lane_en = {LANES{1'b1}};

        lanes_in = {LANES{16'h7FFF}};  check_combiner;   // largest:  LANES * 32767
        lanes_in = {LANES{16'h8000}};  check_combiner;   // smallest: LANES * -32768
        lanes_in = {LANES{16'hFFFF}};  check_combiner;   // all -1
        lanes_in = {LANES*W{1'b0}};    check_combiner;   // all 0

        // =====================================================================
        // C. Original combiner: 5000 random vectors (all lanes enabled)
        // =====================================================================
        lane_en = {LANES{1'b1}};
        for (r = 0; r < 5000; r = r + 1) begin
            for (j = 0; j < LANES; j = j + 1)
                lanes_in[j*W +: W] = $random(seed);
            check_combiner;
        end

        // =====================================================================
        // D. Masked sum: all lanes disabled -> sum must be 0
        // =====================================================================
        lane_en  = {LANES{1'b0}};
        lanes_in = {LANES{16'h1234}};
        check_combiner;   // sum must be 0, vector_result still 0x1234...

        lanes_in = {LANES{16'h7FFF}};
        check_combiner;

        lanes_in = {LANES{16'h8000}};
        check_combiner;

        // =====================================================================
        // E. Only lane 0 enabled
        // =====================================================================
        lane_en  = {{(LANES-1){1'b0}}, 1'b1};   // lane_en[0] = 1 only
        for (r = 0; r < 20; r = r + 1) begin
            for (j = 0; j < LANES; j = j + 1)
                lanes_in[j*W +: W] = $random(seed);
            check_combiner;
        end

        // =====================================================================
        // F. Only the last lane enabled
        // =====================================================================
        lane_en  = {1'b1, {(LANES-1){1'b0}}};   // lane_en[LANES-1] = 1 only
        for (r = 0; r < 20; r = r + 1) begin
            for (j = 0; j < LANES; j = j + 1)
                lanes_in[j*W +: W] = $random(seed);
            check_combiner;
        end

        // =====================================================================
        // G. Each lane enabled individually (sweep)
        // =====================================================================
        for (j = 0; j < LANES; j = j + 1) begin
            lane_en = (1 << j);
            for (r = 0; r < 10; r = r + 1) begin
                integer k;
                for (k = 0; k < LANES; k = k + 1)
                    lanes_in[k*W +: W] = $random(seed);
                check_combiner;
            end
        end

        // =====================================================================
        // H. Alternating lane enable patterns
        // =====================================================================
        // Build alternating patterns without zero-width concatenation repeats.
        // For LANES=1 the only meaningful patterns are all-on and all-off.
        begin : alt_patterns
            integer alt;
            // Pattern "even lanes on": lane_en[0]=1, lane_en[1]=0, lane_en[2]=1, ...
            lane_en = {LANES{1'b0}};
            for (alt = 0; alt < LANES; alt = alt + 2)
                lane_en[alt] = 1'b1;
            for (r = 0; r < 100; r = r + 1) begin
                for (j = 0; j < LANES; j = j + 1)
                    lanes_in[j*W +: W] = $random(seed);
                check_combiner;
            end

            // Pattern "odd lanes on": lane_en[1]=1, lane_en[3]=1, ...
            lane_en = {LANES{1'b0}};
            for (alt = 1; alt < LANES; alt = alt + 2)
                lane_en[alt] = 1'b1;
            for (r = 0; r < 100; r = r + 1) begin
                for (j = 0; j < LANES; j = j + 1)
                    lanes_in[j*W +: W] = $random(seed);
                check_combiner;
            end
        end

        // =====================================================================
        // I. 500 random enable masks with random signed data
        // =====================================================================
        for (r = 0; r < 500; r = r + 1) begin
            lane_en = $random(seed) & ((1 << LANES) - 1);
            for (j = 0; j < LANES; j = j + 1)
                lanes_in[j*W +: W] = $random(seed);
            check_combiner;
        end

        // =====================================================================
        // J. Max positive and min negative under random masks
        // =====================================================================
        for (r = 0; r < 50; r = r + 1) begin
            lane_en = $random(seed) & ((1 << LANES) - 1);
            lanes_in = {LANES{16'h7FFF}};   check_combiner;
            lanes_in = {LANES{16'h8000}};   check_combiner;
            lanes_in = {LANES{16'hFFFF}};   check_combiner;   // -1
            lanes_in = {LANES*W{1'b0}};     check_combiner;   // 0
        end

        // =====================================================================
        // K. lane_flags: exhaustive correctness for each lane individually
        // =====================================================================
        lane_en  = {LANES{1'b1}};
        // All zeros -> all flags 0
        lanes_in = {LANES*W{1'b0}};
        #1;
        check_flags(lane_flags, {LANES{1'b0}}, "flags all-zero input");

        // All 0x7FFF -> all flags 1
        lanes_in = {LANES{16'h7FFF}};
        #1;
        check_flags(lane_flags, {LANES{1'b1}}, "flags all-max positive");

        // All 0x8000 (-32768) -> all flags 1 (non-zero negative)
        lanes_in = {LANES{16'h8000}};
        #1;
        check_flags(lane_flags, {LANES{1'b1}}, "flags all-min negative");

        // All 0xFFFF (-1) -> all flags 1
        lanes_in = {LANES{16'hFFFF}};
        #1;
        check_flags(lane_flags, {LANES{1'b1}}, "flags all-neg-one");

        // Set each lane to zero one at a time; its flag must drop to 0
        lanes_in = {LANES{16'h0001}};   // start: all non-zero
        for (j = 0; j < LANES; j = j + 1) begin
            lanes_in[j*W +: W] = 16'h0000;
            lane_en = {LANES{1'b1}};
            #1;
            check_flags(lane_flags, expected_flags(lanes_in), "flags per-lane zero sweep");
        end

        // =====================================================================
        // L. lane_flags independent of lane_enable
        //    A DISABLED lane can still produce a non-zero flag.
        // =====================================================================
        lane_en  = {LANES{1'b0}};          // all lanes disabled
        lanes_in = {LANES{16'h0001}};       // all results are +1 (non-zero)
        #1;
        // sum must be 0 (disabled), but flags must all be 1 (results are non-zero)
        check_sum  (sum_result, 32'd0,         "flags-vs-enable: sum with all disabled");
        check_flags(lane_flags, {LANES{1'b1}}, "flags-vs-enable: flags despite disable");

        // Half disabled, half enabled, mixed results
        // Build even-lanes-on pattern without zero-width repeat (LANES=1 safe)
        begin : half_en
            integer he;
            lane_en = {LANES{1'b0}};
            for (he = 0; he < LANES; he = he + 2)
                lane_en[he] = 1'b1;
        end
        lanes_in = {LANES*W{1'b0}};
        // Even lanes get a non-zero result -> their flag should still be 1
        for (j = 0; j < LANES; j = j + 2)
            lanes_in[j*W +: W] = 16'h0005;
        #1;
        check_sum  (sum_result, masked_sum(lanes_in, lane_en), "flags-vs-enable mixed sum");
        check_flags(lane_flags, expected_flags(lanes_in),       "flags-vs-enable mixed flags");

        // =====================================================================
        // M. 1000 random enable + result combinations for flags
        // =====================================================================
        for (r = 0; r < 1000; r = r + 1) begin
            lane_en = $random(seed) & ((1 << LANES) - 1);
            for (j = 0; j < LANES; j = j + 1)
                lanes_in[j*W +: W] = $random(seed);
            check_combiner;
        end

        // =====================================================================
        // N. vector_result unchanged regardless of lane_enable
        // =====================================================================
        for (r = 0; r < 100; r = r + 1) begin
            lane_en = $random(seed) & ((1 << LANES) - 1);
            for (j = 0; j < LANES; j = j + 1)
                lanes_in[j*W +: W] = $random(seed);
            #1;
            // vector_result must equal lanes_in regardless of enable
            check_vec(vector_result, lanes_in, "vector_result vs lane_enable");
        end

        // =====================================================================
        // Done
        // =====================================================================
        $display("tb_lane_combiner: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED");
        $finish;
    end

endmodule
