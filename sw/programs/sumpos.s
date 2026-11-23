# sumpos.s - add up only the positive numbers:  s3 = sum of X[i] where X[i] > 0
#
# A masked reduce adds up only the lanes that are switched on, so there is
# no branch and no need to zero the other lanes first:
#
#   v2 = 0 < X            VSLT     -> all ones in the positive lanes
#   mask = v2 != 0        VMSK     -> switch on only the positive lanes
#   s4 = sum (v1 + 0)     VREDADD.M -> the result combiner adds the
#                                      switched-on lanes only
#
# Constants: X (array address), ITER (= N / LANES)

        ADDI  s1, s0, 0         # s1 = word index
        ADDI  s2, s0, ITER      # s2 = number of passes
        ADDI  s3, s0, 0         # s3 = running total
        VXOR  v3, v3, v3        # v3 = 0 in every lane
loop:   VLD   v1, X(s1)
        VSLT  v2, v3, v1        # v2 = all ones where 0 < X[i]
        VMSK  v2                # lane mask: on only where X[i] is positive
        VREDADD.M s4, v1, v3    # s4 = sum of X[i] + 0 over the positive lanes
        ADD   s3, s3, s4        # add them to the total
        ADDI  s1, s1, 1
        BNE   s1, s2, loop
        HALT
