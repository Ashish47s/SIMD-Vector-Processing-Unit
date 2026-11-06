// =============================================================================
// simd_defs.vh - shared names for the instruction set
// =============================================================================
// Every block that needs to know "which instruction is this?" or "which job
// should the lanes do?" includes this file. Keeping the numbers in one place
// means the control unit, the ALUs and the testbenches can never disagree.
//
// Instruction layout (every instruction is 32 bits):
//
//    31      26 25  23 22  20 19  17 16 15                0
//   +----------+------+------+------+--+-------------------+
//   |  opcode  |  rd  |  ra  |  rb  |--|     imm (16 bit)  |
//   +----------+------+------+------+--+-------------------+
//
//   opcode : what to do (6 bits)
//   rd     : destination register (where the answer goes)
//   ra, rb : the two source registers (where the inputs come from)
//   imm    : a small constant written inside the instruction itself
//            (memory offset, loop count, branch distance ...)
//
// The top 2 bits of the opcode give the instruction "class":
//   00 = vector op vector      VADD v3, v1, v2   (each lane: v3 = v1 + v2)
//   01 = vector op scalar      VADD v3, v1, s2   (same number s2 for every lane)
//   10 = reduce to one number  VDOT s4, v1, v2   (add up all lane results)
//   11 = memory, scalar maths and program flow
// For classes 00, 01 and 10 the low 4 bits of the opcode say which ALU job.
// =============================================================================

`ifndef SIMD_DEFS_VH
`define SIMD_DEFS_VH

// ---- Instruction classes (opcode bits [5:4]) ----------------------------------
`define CLASS_VV    2'b00
`define CLASS_VX    2'b01
`define CLASS_RED   2'b10
`define CLASS_CTRL  2'b11

// ---- ALU jobs (opcode bits [3:0]) ---------------------------------------------
// Every lane does the SAME job at the same time - that is what SIMD
// (Single Instruction, Multiple Data) means.
`define ALU_ADD   4'd0    // a + b
`define ALU_SUB   4'd1    // a - b
`define ALU_AND   4'd2    // bitwise AND
`define ALU_OR    4'd3    // bitwise OR
`define ALU_XOR   4'd4    // bitwise XOR
`define ALU_SLL   4'd5    // shift a left by b places (fill with 0)
`define ALU_SRL   4'd6    // shift a right by b places (fill with 0)
`define ALU_SRA   4'd7    // shift a right by b places (keep the sign)
`define ALU_MUL   4'd8    // a * b, keep the low bits
`define ALU_SEQ   4'd9    // a == b          -> all ones, else 0
`define ALU_SLT   4'd10   // a <  b (signed)   -> all ones, else 0
`define ALU_SLTU  4'd11   // a <  b (unsigned) -> all ones, else 0
`define ALU_MIN   4'd12   // smaller of a, b (signed)
`define ALU_MAX   4'd13   // larger of a, b (signed)

// ---- Class 11 opcodes: memory, scalar maths, program flow -------------------
`define OP_VLD    6'h30   // VLD  vd, imm(sa)    vd = memory[sa + imm]
`define OP_VST    6'h31   // VST  vb, imm(sa)    memory[sa + imm] = vb
`define OP_ADDI   6'h38   // ADDI sd, sa, imm    sd = sa + imm
`define OP_ADD    6'h39   // ADD  sd, sa, sb     sd = sa + sb
`define OP_BNE    6'h3C   // BNE  sa, sb, label  if sa != sb jump to label
`define OP_HALT   6'h3F   // HALT                stop the program

`endif
