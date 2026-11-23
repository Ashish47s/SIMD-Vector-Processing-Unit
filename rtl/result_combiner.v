// =============================================================================
// result_combiner.v - turns the lane outputs into the final results
// =============================================================================
// After the lanes finish, their outputs are combined in three ways:
//
//   1. vector_result : the lane outputs kept side by side as one vector.
//                      This is written back to a vector register
//                      (VADD, VMUL, VMAX ...).
//
//   2. sum_result    : the ENABLED lane outputs added together into ONE number.
//                      This goes to a scalar register (VDOT and the other
//                      reduce instructions). With the lanes multiplying,
//                      this gives a masked dot product in one instruction.
//                      If lane_enable[i] = 0, lane i contributes zero.
//
//   3. lane_flags    : one bit per lane. A lane's flag is 1 when its result
//                      is non-zero (regardless of lane_enable). This is the
//                      foundation for the upcoming VMSK instruction: the
//                      processor can compare a vector against zero and load
//                      the resulting bit-mask into the lane-mask register.
//
// The sum uses an adder tree instead of a long chain:
//
//      lane: 0   1   2   3   4   5   6   7
//             \ /     \ /     \ /     \ /      round 1: 4 additions
//              +       +       +       +
//                \   /           \   /         round 2: 2 additions
//                  +               +
//                     \         /              round 3: 1 addition
//                          +
//
// A chain of 8 numbers needs 7 adders one after another; the tree needs only
// 3 rounds (log2 of 8), so the result is ready sooner and the clock can run
// faster.
//
// Each element is treated as a signed number and widened to 32 bits before
// adding, so the total does not overflow.
//
// lane_enable vs lane_flags
// -------------------------
// lane_enable controls WHICH lanes contribute to the masked reduction sum.
// lane_flags reflects whether each lane's raw result is non-zero.
// They serve different purposes: enabling a lane only affects the sum, while
// flags can be generated even for disabled lanes (useful for predication).
// VMSK sets the mask register from flags; it is not the same as lane_enable.
// =============================================================================

module result_combiner #(
    parameter LANES = 8,              // must be a power of two (1, 2, 4, 8 ...)
    parameter W     = 16              // bits per element; below 32 (the sum is 32 bits)
) (
    input  wire [LANES*W-1:0] lane_results,   // outputs of all the lane ALUs
    input  wire [LANES-1:0]   lane_enable,    // 1 = include lane in sum_result, 0 = zero
    output wire [LANES*W-1:0] vector_result,  // same lanes, as one vector (always all lanes)
    output wire [31:0]        sum_result,     // enabled lanes added together
    output wire [LANES-1:0]   lane_flags      // 1 = lane result is non-zero (all lanes)
);

    // -------------------------------------------------------------------------
    // 1. vector_result: lane data pass through unchanged.
    //    lane_enable does NOT mask vector_result; the vector write-back is
    //    controlled by write_lanes in the register file (not here).
    // -------------------------------------------------------------------------
    assign vector_result = lane_results;

    // -------------------------------------------------------------------------
    // 2. lane_flags: one bit per lane, 1 when that lane's result is non-zero.
    //    This is intentionally independent of lane_enable.
    //    Rationale: VMSK generates flags from ALU results to build a predicate
    //    mask. The mask and the enable are logically separate: you might want
    //    to test all eight lanes even when only four are active in the sum.
    // -------------------------------------------------------------------------
    genvar g;
    generate
        for (g = 0; g < LANES; g = g + 1) begin : gen_flags
            assign lane_flags[g] = (lane_results[g*W +: W] != {W{1'b0}});
        end
    endgenerate

    // -------------------------------------------------------------------------
    // 3. sum_result: add the enabled lanes using a balanced adder tree.
    //    "partial" holds LANES running totals of 32 bits each, side by side
    //    (total i sits in bits [i*32 +: 32]). In round 1, total 0 becomes
    //    lanes 0+1, total 2 becomes lanes 2+3, and so on. Each round halves
    //    the number of live totals until only total 0 remains.
    //
    //    Before the tree starts, every disabled lane is replaced with 32'd0.
    //    The tree structure is otherwise identical to the original, so the
    //    critical path and synthesis results are unchanged.
    // -------------------------------------------------------------------------
    reg [32*LANES-1:0] partial;
    integer i, step;

    always @(*) begin
        // Sign-extend each enabled lane to 32 bits; disabled lanes contribute 0.
        for (i = 0; i < LANES; i = i + 1) begin
            if (lane_enable[i])
                partial[i*32 +: 32] = {{(32-W){lane_results[i*W + W-1]}},
                                        lane_results[i*W +: W]};
            else
                partial[i*32 +: 32] = 32'd0;
        end

        // Add neighbours: step = 1, 2, 4 ... (distance between the pair).
        for (step = 1; step < LANES; step = step * 2)
            for (i = 0; i + step < LANES; i = i + 2 * step)
                partial[i*32 +: 32] = partial[i*32 +: 32] + partial[(i + step)*32 +: 32];
    end

    assign sum_result = partial[31:0];

endmodule
