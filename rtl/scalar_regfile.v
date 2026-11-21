// =============================================================================
// scalar_regfile.v - the scalar register file (the "scalar interface")
// =============================================================================
// Not everything in a program is a vector. We also need single numbers for:
//   * memory addresses and loop counters      (ADDI s1, s1, 1)
//   * one value shared by every lane          (VMUL v1, v1, s3 -> v1 * 3)
//   * the result of adding up a whole vector  (VDOT s4, v1, v2)
//
// This block holds 8 scalar registers, s0 .. s7, each 32 bits wide.
// s0 is special: it always reads as 0, and writes to it are ignored.
// That gives programs a free constant zero (ADDI s1, s0, 5 means s1 = 5).
//
// Ports: two read ports (A, B), one write port, and one extra "debug" read
// port so the outside world (a testbench or the FPGA board) can look at
// any scalar register without disturbing the program.
//
// BYPASS works as in vec_regfile.v: with BYPASS = 1, reading the register
// that is being written in this same cycle already gives the new value
// ("write-through"), which the pipelined core needs. With BYPASS = 0 the
// read gives the old value until the clock edge (single-cycle core).
// =============================================================================

module scalar_regfile #(
    parameter BYPASS = 0              // 1 = a read sees this cycle's write
) (
    input  wire        clk,

    // Read port A
    input  wire [2:0]  read_addr_a,
    output wire [31:0] read_data_a,

    // Read port B
    input  wire [2:0]  read_addr_b,
    output wire [31:0] read_data_b,

    // Write port
    input  wire        write_en,
    input  wire [2:0]  write_addr,
    input  wire [31:0] write_data,

    // Debug read port for the host
    input  wire [2:0]  debug_addr,
    output wire [31:0] debug_data
);

    reg [31:0] regs [0:7];

    integer i;
    initial begin
        for (i = 0; i < 8; i = i + 1)
            regs[i] = 32'd0;
    end

    // With BYPASS on, a read of the register being written right now gets
    // the new value. (A read of register 0 is answered with 0 first, so a
    // write to s0 can never show up through the bypass.)
    wire writing = (BYPASS != 0) && write_en;
    wire hit_a   = writing && (write_addr == read_addr_a);
    wire hit_b   = writing && (write_addr == read_addr_b);

    // Register 0 always reads as zero, whatever is stored in it.
    assign read_data_a = (read_addr_a == 3'd0) ? 32'd0 :
                         hit_a                 ? write_data : regs[read_addr_a];
    assign read_data_b = (read_addr_b == 3'd0) ? 32'd0 :
                         hit_b                 ? write_data : regs[read_addr_b];
    // The debug port is only looked at after the program ends, so it never needs the bypass.
    assign debug_data  = (debug_addr  == 3'd0) ? 32'd0 : regs[debug_addr];

    // Writes to register 0 are dropped.
    always @(posedge clk) begin
        if (write_en && write_addr != 3'd0)
            regs[write_addr] <= write_data;
    end

endmodule
