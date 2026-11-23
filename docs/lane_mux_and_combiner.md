# Lane MUX and result combiner

Files: [`rtl/lane_mux.v`](../rtl/lane_mux.v), [`rtl/result_combiner.v`](../rtl/result_combiner.v), test [`tb/tb_lane_combiner.v`](../tb/tb_lane_combiner.v)

These two blocks sit on either side of the lanes. The lane MUX decides what goes **into** each lane; the result combiner decides what comes **out**.

---

## Lane MUX: vector or broadcast

Every lane needs a second number (operand B), and it can come from two places:

| `use_scalar` | Each lane gets | Example |
| --- | --- | --- |
| 0 | its own element of vector register `vb` | `VADD v3, v1, v2`: lane *i* computes `v1[i] + v2[i]` |
| 1 | the same scalar value, copied to every lane | `VMUL v3, v1, s2`: lane *i* computes `v1[i] × s2` |

Copying one value into every lane is called a **broadcast**. In Verilog, `{LANES{scalar_b}}` glues LANES copies of the 16-bit value side by side. The hardware is LANES small two-way switches (multiplexers), all flipped by the same signal.

Without broadcast, multiplying a vector by 3 would first need a vector full of 3s, which costs an extra instruction and a register.

---

## Result combiner: vector, masked sum, and lane flags

The result combiner has three outputs:

### 1. `vector_result` — lane outputs as a vector

The raw lane outputs passed through unchanged. This is what `VADD`, `VMUL`, and similar instructions write back to a vector register. `lane_enable` does **not** affect `vector_result`; write-back masking is handled separately by `write_lanes` in the vector register file.

### 2. `sum_result` — masked reduction

All **enabled** lane outputs are added into one 32-bit number. This is what the reduce instructions (`VDOT`, etc.) write to a scalar register. With the lanes multiplying, `VDOT s4, v1, v2` computes `Σ v1[i] × v2[i]` for all enabled lanes in one instruction.

**How lane_enable works:**

```
lane_enable[i] = 1  →  lane i contributes its signed result to the sum
lane_enable[i] = 0  →  lane i contributes zero (effectively masked out)
```

Example with LANES = 4:

```
lane_results = [10, 20, 30, 40]   (signed 16-bit)
lane_enable  = [1,   0,  1,  0]

Enabled lanes: 10 + 30 = 40
sum_result  = 40

If lane_enable = [0, 0, 0, 0]:
sum_result = 0
```

The adding still uses a **balanced adder tree** (not a chain), so the hardware is just as fast:

```
lane:   0   1   2   3   4   5   6   7
         \ /     \ /     \ /     \ /       round 1: 4 adders
          +       +       +       +
            \   /           \   /          round 2: 2 adders
              +               +
                  \       /                round 3: 1 adder
                      +
```

A chain of 8 numbers needs 7 adders one after another; the tree needs only 3 rounds (log₂ 8). Each enabled 16-bit element is sign-extended to 32 bits first, so −1 stays −1 and the total cannot overflow (8 × 32,767 = 262,136, well within 32 bits).

### 3. `lane_flags` — per-lane non-zero indicator

One output bit per lane. A flag is `1` if the lane's result is **non-zero**, and `0` if it is exactly zero.

```
lane_results[i] ≠ 0  →  lane_flags[i] = 1
lane_results[i] = 0  →  lane_flags[i] = 0
```

This handles positive values, negative values, and the value zero correctly because it compares the raw binary result to zero — both `0x0001` (+1) and `0xFFFF` (−1) are non-zero.

**Important: `lane_flags` is independent of `lane_enable`.**

A disabled lane (lane_enable[i] = 0) still raises its flag if its result is non-zero. This is intentional:

- `lane_enable` controls which lanes contribute to the **reduction sum**.
- `lane_flags` reflects the **ALU result**, which is useful for predication.

The upcoming VMSK instruction will read `lane_flags` to build a predicate mask (which lanes should be active next). It would be wrong for VMSK to skip checking a lane simply because that lane happened to be disabled in the previous reduction.

---

## How lane_enable supports VMSK (future)

VMSK (Vector MaSK) is a planned instruction that:

1. Runs an ALU operation on all lanes (e.g., `SEQ` for "equals zero").
2. Reads `lane_flags` to get one bit per lane (non-zero result = lane is "true").
3. Writes those bits into the lane-mask register.
4. Subsequent masked instructions use the mask register as `lane_enable` for their reductions.

This design keeps `lane_flags` and `lane_enable` separate so both can be used at the same time:

```
cycle 1: VSEQ v_tmp, v_data, v_zero   ; compare: which lanes are non-zero?
         → lane_flags = [1,0,1,1,0,0,0,1]
cycle 2: VMSK                          ; lane_mask ← lane_flags
cycle 3: VDOT s0, v_a, v_b            ; dot product over active lanes only
         → lane_enable = lane_mask = [1,0,1,1,0,0,0,1]
```

The current single-cycle core ties `lane_enable` to all-ones. The pipelined core (Mahir's work, Issue #21) will connect `lane_enable` to the mask register output.

---

## Implementation details

### result_combiner.v

The module gained two new ports:

```verilog
input  wire [LANES-1:0]   lane_enable,  // 1 = include lane in sum_result
output wire [LANES-1:0]   lane_flags    // 1 = lane result is non-zero
```

**Lane flags** are combinational wires generated by `genvar` / `generate`, one comparator per lane:

```verilog
genvar g;
generate
    for (g = 0; g < LANES; g = g + 1) begin : gen_flags
        assign lane_flags[g] = (lane_results[g*W +: W] != {W{1'b0}});
    end
endgenerate
```

**Masked adder tree** uses the same `always @(*)` block as before. The only change is the sign-extension step, which now zeroes disabled lanes:

```verilog
for (i = 0; i < LANES; i = i + 1) begin
    if (lane_enable[i])
        partial[i*32 +: 32] = {{(32-W){lane_results[i*W + W-1]}},
                                lane_results[i*W +: W]};
    else
        partial[i*32 +: 32] = 32'd0;   // disabled lane contributes zero
end
```

The rest of the adder tree is unchanged. This keeps the design synthesizable, parameterized for LANES = 1, 2, 4, 8, and free of sequential logic.

### simd_core.v

Two small changes to the combiner instantiation:

```verilog
/* verilator lint_off UNUSEDSIGNAL */
wire [LANES-1:0] combiner_flags;
/* verilator lint_on UNUSEDSIGNAL */

result_combiner #(.LANES(LANES), .W(W)) u_combiner (
    .lane_results  (alu_out),
    .lane_enable   ({LANES{1'b1}}),   // all lanes on; pipelined core uses lane_mask
    .vector_result (vector_result),
    .sum_result    (sum_result),
    .lane_flags    (combiner_flags)   // captured; used by VMSK in future core
);
```

No other changes are made to the core or control unit. Existing instruction behaviour is fully preserved.

---

## Test

`tb_lane_combiner` runs for **1, 2, 4 and 8 lanes** and covers:

| Section | Description | Checks |
| --- | --- | --- |
| A | 1,000 random lane-MUX cases (vector and broadcast) | 1,000 |
| B | Extreme values: max, min, −1, 0 (all lanes enabled) | 4 × 3 |
| C | 5,000 random vectors (all lanes enabled) | 5,000 × 3 |
| D | All lanes disabled; must sum to 0 | 3 sets |
| E | Only lane 0 enabled, random data | 20 sets |
| F | Only last lane enabled, random data | 20 sets |
| G | Each lane individually enabled (sweep) | LANES × 10 sets |
| H | Alternating patterns 01/10, random data | 200 sets |
| I | 500 random enable masks with random signed data | 500 × 3 |
| J | Max/min values under 50 random masks | 200 sets |
| K | Flags exhaustive: zero, max, min, −1, per-lane zero sweep | exhaustive |
| L | Flags independent of lane_enable | directed |
| M | 1,000 random enable + result for flags | 1,000 × 3 |
| N | vector_result unchanged regardless of enable | 100 |

The reference model (a plain Verilog `for` loop) computes the expected sum independently, so the hardware adder tree is always cross-checked against the simplest possible method.

```bash
make tb_lane_combiner
```

Expected output per lane count:

```
tb_lane_combiner: 8 lanes x 16 bits
tb_lane_combiner: <N> checks, 0 errors
TEST PASSED
```
