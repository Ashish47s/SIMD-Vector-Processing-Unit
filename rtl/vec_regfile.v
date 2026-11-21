// =============================================================================
// vec_regfile.v - the vector register file (and the lane mask)
// =============================================================================
// A small, very fast storage area inside the processor. It holds NREGS
// vector registers (v0 .. v7). Each register holds one whole vector:
// LANES elements of W bits, so 8 x 16 = 128 bits by default.
//
// Ports:
//   * two READ ports  (A and B) - an instruction like VADD v3, v1, v2 needs
//     to read two registers at the same time. Reading has no clock: the
//     data shows up as soon as the address is set.
//   * one WRITE port - the answer is saved on the rising clock edge, but
//     only when write_en is 1, and only into the lanes whose bit in
//     write_lanes is 1. The other lanes keep their old value. This is how
//     masked instructions work: "do the add, but only change lanes 0 and 3".
//
// The lane mask:
//   One extra register, "mask", holds one bit per lane (1 = lane is on).
//   Masked instructions use it as their write_lanes. It starts with every
//   lane on, and the VMSK instruction changes it.
//
// Read-during-write, two choices (the BYPASS parameter):
//   BYPASS = 0  If an instruction reads and writes the same register
//               (VADD v1, v1, v2), it reads the OLD value, and the new value
//               is saved at the clock edge. The single-cycle core needs this.
//   BYPASS = 1  "Write-through": a read of the register that is being
//               written in this same cycle already returns the NEW value
//               (lane by lane: lanes that are not being written still show
//               the old value). The pipelined core needs this, because there
//               the instruction being written back is older than the one
//               reading, so the reader must see the new value straight away.
// =============================================================================

module vec_regfile #(
    parameter LANES  = 8,
    parameter W      = 16,
    parameter NREGS  = 8,             // number of vector registers
    parameter BYPASS = 0              // 1 = a read sees this cycle's write (see above)
) (
    input  wire                     clk,

    // Read port A
    input  wire [$clog2(NREGS)-1:0] read_addr_a,
    output wire [LANES*W-1:0]       read_data_a,

    // Read port B
    input  wire [$clog2(NREGS)-1:0] read_addr_b,
    output wire [LANES*W-1:0]       read_data_b,

    // Write port
    input  wire                     write_en,
    input  wire [LANES-1:0]         write_lanes,   // which lanes to change (1 = write)
    input  wire [$clog2(NREGS)-1:0] write_addr,
    input  wire [LANES*W-1:0]       write_data,

    // Lane mask: one bit per lane
    output wire [LANES-1:0]         mask,
    input  wire                     mask_write_en,
    input  wire [LANES-1:0]         mask_write_data
);

    // The storage itself: NREGS rows, each one vector wide, plus the mask.
    reg [LANES*W-1:0] regs [0:NREGS-1];
    reg [LANES-1:0]   mask_reg;

    // Start every register at zero and every lane switched on, so simulations
    // never show unknown (X) values. The FPGA loads these values when it is
    // programmed.
    integer i;
    initial begin
        for (i = 0; i < NREGS; i = i + 1)
            regs[i] = {LANES*W{1'b0}};
        mask_reg = {LANES{1'b1}};
    end

    // ---- Reading ------------------------------------------------------------
    // First look up the stored rows (no clock needed).
    wire [LANES*W-1:0] stored_a = regs[read_addr_a];
    wire [LANES*W-1:0] stored_b = regs[read_addr_b];

    // Then, lane by lane: with BYPASS on, a lane that is being written into
    // the same register right now shows the new value instead.
    genvar k;
    generate
        for (k = 0; k < LANES; k = k + 1) begin : lane
            wire writing_lane = (BYPASS != 0) && write_en && write_lanes[k];
            wire hit_a = writing_lane && (write_addr == read_addr_a);
            wire hit_b = writing_lane && (write_addr == read_addr_b);
            assign read_data_a[k*W +: W] = hit_a ? write_data[k*W +: W] : stored_a[k*W +: W];
            assign read_data_b[k*W +: W] = hit_b ? write_data[k*W +: W] : stored_b[k*W +: W];
        end
    endgenerate

    // The mask works the same way.
    assign mask = ((BYPASS != 0) && mask_write_en) ? mask_write_data : mask_reg;

    // ---- Writing: only on the rising edge of the clock --------------------------
    // Each lane is saved only if its write_lanes bit is 1.
    integer n;
    always @(posedge clk) begin
        if (write_en)
            for (n = 0; n < LANES; n = n + 1)
                if (write_lanes[n])
                    regs[write_addr][n*W +: W] <= write_data[n*W +: W];
        if (mask_write_en)
            mask_reg <= mask_write_data;
    end

endmodule
