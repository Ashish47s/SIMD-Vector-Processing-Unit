# isa_test.s - runs EVERY vector instruction on random data
#
# This is the "nothing is left untested" program. Each loop pass loads two
# random vectors and then:
#   * runs all 16 ALU jobs as vector-vector ops  (V<op> v3, v1, v2)
#   * runs all 16 ALU jobs as vector-scalar ops  (V<op> v4, v1, s3)
#   * stores every result in its own memory area (the two saturating jobs
#     share one area: their results are XOR-ed together first, because
#     30 areas is all that fits in the 1,024-word data memory)
#   * runs all 16 reduce ops and adds them into one checksum (s6)
#   * builds a lane mask from a compare (VMSK) and runs masked vector,
#     vector-scalar and reduce ops, also added into the checksum
#   * runs VDOT and keeps a separate running total (s7)
# The broadcast value s3 changes every pass, so shifts and compares see
# many different scalar values.
#
# The FPGA build loads this program, so every instruction must appear here:
# an instruction that no program uses could be optimised away by the tools.
#
# Constants: A, B (inputs), OUT (first result area), STRIDE (size of each
#            area), ITER (= N / LANES)

        ADDI s1, s0, 0          # s1 = word index
        ADDI s2, s0, ITER       # s2 = number of passes
        ADDI s3, s0, 12345      # s3 = broadcast value (changes every pass)
        ADDI s6, s0, 0          # s6 = checksum of the reduce results
        ADDI s7, s0, 0          # s7 = running dot product
loop:   VLD  v1, A(s1)
        VLD  v2, B(s1)

        # ---- vector op vector ----
        VADD    v3, v1, v2
        VST     v3, OUT+0*STRIDE(s1)
        VSUB    v3, v1, v2
        VST     v3, OUT+1*STRIDE(s1)
        VAND    v3, v1, v2
        VST     v3, OUT+2*STRIDE(s1)
        VOR     v3, v1, v2
        VST     v3, OUT+3*STRIDE(s1)
        VXOR    v3, v1, v2
        VST     v3, OUT+4*STRIDE(s1)
        VSLL    v3, v1, v2
        VST     v3, OUT+5*STRIDE(s1)
        VSRL    v3, v1, v2
        VST     v3, OUT+6*STRIDE(s1)
        VSRA    v3, v1, v2
        VST     v3, OUT+7*STRIDE(s1)
        VMUL    v3, v1, v2
        VST     v3, OUT+8*STRIDE(s1)
        VSEQ    v3, v1, v2
        VST     v3, OUT+9*STRIDE(s1)
        VSLT    v3, v1, v2
        VST     v3, OUT+10*STRIDE(s1)
        VSLTU   v3, v1, v2
        VST     v3, OUT+11*STRIDE(s1)
        VMIN    v3, v1, v2
        VST     v3, OUT+12*STRIDE(s1)
        VMAX    v3, v1, v2
        VST     v3, OUT+13*STRIDE(s1)
        VADDS   v3, v1, v2
        VSUBS   v5, v1, v2
        VXOR    v3, v3, v5          # both saturating results in one area
        VST     v3, OUT+14*STRIDE(s1)
        # ---- vector op broadcast scalar ----
        VADD    v4, v1, s3
        VST     v4, OUT+15*STRIDE(s1)
        VSUB    v4, v1, s3
        VST     v4, OUT+16*STRIDE(s1)
        VAND    v4, v1, s3
        VST     v4, OUT+17*STRIDE(s1)
        VOR     v4, v1, s3
        VST     v4, OUT+18*STRIDE(s1)
        VXOR    v4, v1, s3
        VST     v4, OUT+19*STRIDE(s1)
        VSLL    v4, v1, s3
        VST     v4, OUT+20*STRIDE(s1)
        VSRL    v4, v1, s3
        VST     v4, OUT+21*STRIDE(s1)
        VSRA    v4, v1, s3
        VST     v4, OUT+22*STRIDE(s1)
        VMUL    v4, v1, s3
        VST     v4, OUT+23*STRIDE(s1)
        VSEQ    v4, v1, s3
        VST     v4, OUT+24*STRIDE(s1)
        VSLT    v4, v1, s3
        VST     v4, OUT+25*STRIDE(s1)
        VSLTU   v4, v1, s3
        VST     v4, OUT+26*STRIDE(s1)
        VMIN    v4, v1, s3
        VST     v4, OUT+27*STRIDE(s1)
        VMAX    v4, v1, s3
        VST     v4, OUT+28*STRIDE(s1)
        VADDS   v4, v1, s3
        VSUBS   v5, v1, s3
        VXOR    v4, v4, v5
        VST     v4, OUT+29*STRIDE(s1)
        # ---- reduce: add up all lanes of (v1 op v2) ----
        VREDADD  s5, v1, v2
        ADD     s6, s6, s5
        VREDSUB  s5, v1, v2
        ADD     s6, s6, s5
        VREDAND  s5, v1, v2
        ADD     s6, s6, s5
        VREDOR   s5, v1, v2
        ADD     s6, s6, s5
        VREDXOR  s5, v1, v2
        ADD     s6, s6, s5
        VREDSLL  s5, v1, v2
        ADD     s6, s6, s5
        VREDSRL  s5, v1, v2
        ADD     s6, s6, s5
        VREDSRA  s5, v1, v2
        ADD     s6, s6, s5
        VREDMUL  s5, v1, v2
        ADD     s6, s6, s5
        VREDSEQ  s5, v1, v2
        ADD     s6, s6, s5
        VREDSLT  s5, v1, v2
        ADD     s6, s6, s5
        VREDSLTU s5, v1, v2
        ADD     s6, s6, s5
        VREDMIN  s5, v1, v2
        ADD     s6, s6, s5
        VREDMAX  s5, v1, v2
        ADD     s6, s6, s5
        VREDADDS s5, v1, v2
        ADD     s6, s6, s5
        VREDSUBS s5, v1, v2
        ADD     s6, s6, s5
        # ---- masked: only the lanes where v1 < v2 take part ----
        VSLT    v5, v1, v2
        VMSK    v5              # lane mask from a compare
        VADD.M  v4, v1, v2      # changes only the switched-on lanes of v4
        VMUL.M  v4, v4, s3      # vector-scalar, masked, using the line above
        VREDOR  s5, v4, v4      # add up every lane of v4 (x OR x = x)
        ADD     s6, s6, s5
        VREDADD.M s5, v1, v2    # masked reduce: switched-on lanes only
        ADD     s6, s6, s5
        VDOT.M  s5, v1, v2
        ADD     s6, s6, s5
        VSEQ    v5, v1, v1      # all ones in every lane ...
        VMSK    v5              # ... so every lane is on again
        VDOT    s5, v1, v2
        ADD     s7, s7, s5
        ADDI    s3, s3, 1237    # new broadcast value for the next pass
        ADDI    s1, s1, 1
        BNE     s1, s2, loop
        HALT
