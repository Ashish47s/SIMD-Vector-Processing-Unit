// =============================================================================
// vec_alu_lane.v - one lane of the SIMD unit
// =============================================================================
// Think of this as a small calculator that works on ONE number pair.
//
// The full unit places LANES copies of this calculator side by side
// (see vec_alu_array.v). Every copy gets the same job ("op") but its own
// pair of numbers, so one instruction does LANES calculations at once.
//
// There is no clock here: the answer appears as soon as the inputs change.
// =============================================================================

`include "simd_defs.vh"

module vec_alu_lane #(
    parameter W = 16                 // bits per element; a power of two (8 or 16)
) (
    input  wire [3:0]   op,          // which job to do (list in simd_defs.vh)
    input  wire [W-1:0] a,           // first number
    input  wire [W-1:0] b,           // second number
    output reg  [W-1:0] y            // the answer
);

    // ---- Shift amount -------------------------------------------------------
    // Only the low bits of b are used. A 16-bit number can be shifted by
    // 0 to 15 places, and 15 fits in 4 bits ($clog2(16) = 4).
    localparam SHIFT_BITS = $clog2(W);
    wire [SHIFT_BITS-1:0] shift = b[SHIFT_BITS-1:0];

    // ---- Comparisons --------------------------------------------------------
    // The same bits can mean two different numbers. 16'hFFFF is 65535 when
    // read as "unsigned" but -1 when read as "signed" (two's complement).
    // $signed() tells Verilog to use the signed reading.
    wire is_equal          = (a == b);
    wire is_less_signed    = ($signed(a) < $signed(b));
    wire is_less_unsigned  = (a < b);

    // A comparison writes all ones for "true" and all zeros for "false".
    // All ones works directly as a mask: (x AND mask) keeps x where the test
    // passed and clears it where it failed. SSE and ARM NEON do the same.
    wire [W-1:0] ALL_ONES = {W{1'b1}};

    // ---- Saturating add and subtract (ADDS, SUBS) ----------------------------
    // Normal ADD wraps around: 32767 + 1 gives -32768, like a car odometer.
    // ADDS "sticks" at the edge instead: 32767 + 1 gives 32767, and
    // -32768 - 1 gives -32768. Image and audio code wants this, so a very
    // bright pixel stays white instead of flipping to black.
    //
    // How it works: do the sum with ONE extra bit, so it can never overflow.
    // Copying the sign bit in front ({a[W-1], a}) widens a number without
    // changing its value. If the top two bits of the wide answer differ, the
    // answer did not fit in W bits; the very top bit then says which way it
    // went: 0 = too big, 1 = too small.
    wire [W:0] wide_sum  = {a[W-1], a} + {b[W-1], b};
    wire [W:0] wide_diff = {a[W-1], a} - {b[W-1], b};

    wire [W-1:0] BIGGEST  = {1'b0, {(W-1){1'b1}}};    // 0x7FFF =  32767
    wire [W-1:0] SMALLEST = {1'b1, {(W-1){1'b0}}};    // 0x8000 = -32768

    wire sum_too_far  = (wide_sum[W]  != wide_sum[W-1]);
    wire diff_too_far = (wide_diff[W] != wide_diff[W-1]);

    wire [W-1:0] sat_sum  = !sum_too_far  ? wide_sum[W-1:0]  :
                            wide_sum[W]   ? SMALLEST : BIGGEST;
    wire [W-1:0] sat_diff = !diff_too_far ? wide_diff[W-1:0] :
                            wide_diff[W]  ? SMALLEST : BIGGEST;

    // ---- Pick the answer for the requested job ------------------------------
    always @(*) begin
        case (op)
            `ALU_ADD:  y = a + b;
            `ALU_SUB:  y = a - b;
            `ALU_AND:  y = a & b;
            `ALU_OR:   y = a | b;
            `ALU_XOR:  y = a ^ b;
            `ALU_SLL:  y = a << shift;
            `ALU_SRL:  y = a >> shift;
            `ALU_SRA:  y = $signed(a) >>> shift;   // copies the sign bit in from the left
            `ALU_MUL:  y = a * b;                  // y is W bits, so only the low half is kept
            `ALU_SEQ:  y = is_equal         ? ALL_ONES : {W{1'b0}};
            `ALU_SLT:  y = is_less_signed   ? ALL_ONES : {W{1'b0}};
            `ALU_SLTU: y = is_less_unsigned ? ALL_ONES : {W{1'b0}};
            `ALU_MIN:  y = is_less_signed   ? a : b;
            `ALU_MAX:  y = is_less_signed   ? b : a;
            `ALU_ADDS: y = sat_sum;
            `ALU_SUBS: y = sat_diff;
            default:   y = {W{1'b0}};             // never used: all 16 codes are listed
        endcase
    end

endmodule
