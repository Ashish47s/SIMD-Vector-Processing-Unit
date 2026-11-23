# abs.s - absolute value with a lane mask:  Y[i] = |X[i]|
#
# Only the negative lanes need changing (to 0 - X[i]); the others stay as
# they are. A masked instruction does exactly that:
#
#   v2 = X < 0            VSLT  -> all ones in the negative lanes, 0 elsewhere
#   mask = v2 != 0        VMSK  -> switch on only the negative lanes
#   v1 = 0 - v1 (masked)  VSUBS.M -> changes the switched-on lanes, leaves the
#                                    rest of v1 untouched
#
# VSUBS (saturating) matters for one value: -32768 has no positive partner in
# 16 bits, so 0 - (-32768) would wrap back to -32768. VSUBS gives 32767.
#
# Constants: X, Y (array addresses), ITER (= N / LANES)

        ADDI  s1, s0, 0         # s1 = word index
        ADDI  s2, s0, ITER      # s2 = number of passes
        VXOR  v3, v3, v3        # v3 = 0 in every lane (anything XOR itself is 0)
loop:   VLD   v1, X(s1)
        VSLT  v2, v1, s0        # v2 = all ones where X[i] < 0   (s0 is always 0)
        VMSK  v2                # lane mask: on only where X[i] is negative
        VSUBS.M v1, v3, v1      # in those lanes only: v1 = 0 - X[i]
        VST   v1, Y(s1)
        ADDI  s1, s1, 1
        BNE   s1, s2, loop
        HALT
