# Parallel ALUs

Files: [`rtl/vec_alu_lane.v`](../rtl/vec_alu_lane.v), [`rtl/vec_alu_array.v`](../rtl/vec_alu_array.v), test [`tb/tb_vec_alu.v`](../tb/tb_vec_alu.v)

## One lane

`vec_alu_lane` is a 16-bit calculator. It takes two numbers `a` and `b` and a 4-bit job code `op`, and gives one answer `y`. It has no clock: as soon as the inputs change, the answer changes. Inside is one `case` statement that picks the answer for the requested job:

| Group | Jobs | Notes |
| --- | --- | --- |
| Arithmetic | `ADD`, `SUB`, `MUL` | Results wrap around at 16 bits. `MUL` keeps the low 16 bits of the 32-bit product. |
| Logic | `AND`, `OR`, `XOR` | Bit by bit. |
| Shifts | `SLL`, `SRL`, `SRA` | Shift amount is `b mod 16`. `SRA` copies the sign bit in, so −8 >> 1 = −4. |
| Compare | `SEQ`, `SLT`, `SLTU` | All ones (`0xFFFF`) for true, 0 for false, usable as a mask. |
| Select | `MIN`, `MAX` | Signed. |
| Saturating | `ADDS`, `SUBS` | Like `ADD` and `SUB`, but an answer that does not fit stops at the edge instead of wrapping: `32767 + 1 = 32767`, `−32768 − 1 = −32768`. |

**Saturating jobs (Phase 2).** Normal 16-bit adding wraps around like a car odometer, so `32767 + 1` becomes `−32768`. For pixels or audio samples that is the worst possible answer: a bright pixel turns black. `ADDS` and `SUBS` clamp instead. The lane does the sum with one extra bit, so the true answer always fits; if the top two bits of that 17-bit answer differ, the true answer is outside −32768 … 32767, and the top bit says which edge to stick to. These two jobs use the last two free job codes, 14 and 15, so every 4-bit code now has a job.

**Signed and unsigned.** The same 16 bits can mean two numbers: `0xFFFF` is 65,535 unsigned but −1 signed (two's complement). `SLT`, `MIN`, `MAX` and `SRA` use the signed reading (`$signed()` in Verilog); `SLTU` uses the unsigned one.

## Many lanes

`vec_alu_array` makes `LANES` copies of the lane with a `generate` loop. Lane `i` is wired to bits `[16i+15 : 16i]` of the 128-bit buses. Every copy receives the same `op`, which is exactly what *Single Instruction, Multiple Data* means. The lanes never talk to each other; for example, a carry out of lane 0 never reaches lane 1. The testbench checks this explicitly.

## On the FPGA

On ECP5, each lane's multiply goes into one hardware multiplier block (`MULT18X18D`), so 8 lanes use 8 of the chip's 28. The rest of a lane, mainly the three shifters and the compare logic, takes about 350 small look-up tables.

## Test

`tb_vec_alu` checks 257,689 lane results against a reference model written differently: with plain integer maths such as `a * 2^n` for a left shift. A mistake in the RTL is therefore unlikely to be repeated in the model. It covers:

1. all 64 pairs of eight tricky values (0, 1, −1, 32767, −32768, 0x00FF, 0x5555, 0xAAAA) for every job;
2. every shift amount from 0 to 23 (amounts above 15 must wrap);
3. `0xFFFF + 1` in every lane, to prove no carry leaks between lanes;
4. 2,000 random 8-lane vectors per job;
5. nine saturation cases with the answers typed in by hand (for example `0x7FFF + 1 = 0x7FFF` and `0xC000 + 0xC000 = 0x8000`, which fits exactly), so the RTL and the model cannot share a mistake.

The coverage table also counts how often `ADDS` and `SUBS` had to clamp; the test fails unless each job was seen both clamping and not clamping. `sw/directed_tests.py` runs all three forms of both jobs on the whole processor.

```bash
make tb_vec_alu
```
