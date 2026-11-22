# Register files

Files: [`rtl/vec_regfile.v`](../rtl/vec_regfile.v), [`rtl/scalar_regfile.v`](../rtl/scalar_regfile.v), test [`tb/tb_regfiles.v`](../tb/tb_regfiles.v)

Registers are the processor's own tiny, very fast storage. Memory is large but slow (one clock to read); registers can be read instantly, and an instruction usually reads two of them and writes one.

## Vector register file

* 8 registers, `v0` to `v7`, each 128 bits = 8 lanes × 16 bits.
* **Two read ports.** `VADD v3, v1, v2` needs `v1` and `v2` at the same time. Reading has no clock: the data appears as soon as the address is set.
* **One write port.** The result is stored at the rising clock edge, and only when `write_en` is 1.
* **Lane write enables (Phase 2).** `write_lanes` has one bit per lane, and only the lanes whose bit is 1 are changed; the others keep their old value. A masked instruction such as `VADD.M v3, v1, v2` passes the lane mask here, so "add, but only in lanes 0 and 3" needs no extra read of the old `v3`: the register file simply leaves the other lanes alone.
* **Lane mask register (Phase 2).** One extra register, `mask`, holds one bit per lane. It starts with every lane on, `VMSK` changes it, and masked instructions use it as their `write_lanes`.
* **Read-during-write.** If an instruction reads and writes the same register (`VADD v1, v1, v2`), it reads the old value. The new one is stored at the clock edge. This is what makes `v1 = v1 + v2` work.

## Write-through (the `BYPASS` parameter, Phase 2)

Both files have a `BYPASS` parameter that changes what a read shows while a write to the same register is happening:

| `BYPASS` | A read of the register being written in this cycle shows | Used by |
| --- | --- | --- |
| 0 | the old value, until the clock edge | single-cycle core |
| 1 | the new value at once ("write-through"); for vectors only in the lanes being written | pipelined core |

Why the pipelined core needs it: there, several instructions are in flight at once. The instruction being written back is *older* than the one reading its registers two stages behind it, so in program order the write has already happened, and the reader must see the new value. Without write-through it would read a stale value and compute the wrong answer. Textbook pipelines solve the same problem by "writing in the first half of the cycle and reading in the second half"; write-through does it with one multiplexer per read port.

The single-cycle core must keep `BYPASS = 0`: there, the instruction reading a register is the same one writing it, so a write-through would feed the answer back into its own inputs in the same cycle (a combinational loop).

## Scalar register file (the scalar interface)

* 8 registers, `s0` to `s7`, each 32 bits.
* `s0` always reads 0, and writes to it are dropped. Programs get a free zero: `ADDI s1, s0, 5` sets `s1` to 5, and `VMAX v2, v1, s0` compares every lane with 0.
* Two read ports and one write port, like the vector file.
* A third **debug read port** lets the outside world read any register without disturbing the program. The system testbench uses it to check the results; on the FPGA board, three switches pick a register and eight LEDs show its low byte.

Scalar registers do four jobs: memory addresses (`VLD v1, A(s1)`), loop counters (`BNE s1, s2, loop`), values broadcast to every lane (`VMUL v1, v1, s3`), and the single-number result of a reduce (`VDOT s4, v1, v2`).

## On the FPGA

Both files use about the same logic as a small memory, and the synthesis tools notice. On ECP5 and Artix-7 they are built from distributed LUT RAM rather than flip-flops, which is why the single-cycle 8-lane design needs only a few dozen flip-flops. With lane write enables, each lane's slice of the vector file can be written on its own; the tools build it as one small memory per lane.

## Test

`tb_regfiles` builds each file twice, once with `BYPASS = 0` and once with `BYPASS = 1`, feeds both the same inputs, keeps its own copy of what every register should hold, and checks 24,092 reads:

1. a different pattern written into each register, then read back through both ports in opposite orders;
2. a write with `write_en = 0` must change nothing and must not show through the bypass;
3. a write with only lanes 0 and 2 switched on changes only those lanes;
4. read-during-write: the normal file gives the old value before the edge, the write-through file gives the new value at once, only in the written lanes, and only for that register;
5. the lane mask starts all on, and changes at the edge (normal) or at once (write-through);
6. `s0` stays 0 even after a write, also through the bypass;
7. 2,000 random cycles on each file (random write enable, lanes, addresses, data and mask writes; a third of the reads hit the register being written).

```bash
make tb_regfiles
```
