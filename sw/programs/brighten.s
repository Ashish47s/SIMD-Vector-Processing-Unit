# brighten.s - make an image brighter without wrapping:  Y[i] = X[i] + K, clamped
#
# Each element is one pixel (or one audio sample). With a normal VADD, a pixel
# near the top, 32000 + 2000, would wrap around to a large NEGATIVE number:
# the brightest pixels would turn black. VADDS (saturating add) stops at
# 32767 instead, so they stay white. K is the same for every pixel, so it
# lives in a scalar register and is broadcast to every lane.
#
# Constants: X, Y (array addresses), ITER (= N / LANES), K (how much brighter)

        ADDI  s1, s0, 0         # s1 = word index
        ADDI  s2, s0, ITER      # s2 = number of passes
        ADDI  s3, s0, K         # s3 = K
loop:   VLD   v1, X(s1)
        VADDS v1, v1, s3        # every lane: X[i] + K, stuck at 32767 if it overflows
        VST   v1, Y(s1)
        ADDI  s1, s1, 1
        BNE   s1, s2, loop
        HALT
