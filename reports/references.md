# References

The works the Phase 1 report builds on, grouped by topic. Numbers match the report.

## SIMD and vector architecture

1. J. L. Hennessy and D. A. Patterson, *Computer Architecture: A Quantitative Approach*, 6th ed., Morgan Kaufmann, 2017, ch. 4. Textbook treatment of data-level parallelism.
2. M. J. Flynn, "Some computer organizations and their effectiveness," *IEEE Trans. Comput.*, vol. C-21, no. 9, pp. 948–960, 1972. The taxonomy that defines SIMD.
3. R. M. Russell, "The CRAY-1 computer system," *Commun. ACM*, vol. 21, no. 1, pp. 63–72, 1978. Vector registers and pipelined vector units.
4. A. Peleg and U. Weiser, "MMX technology extension to the Intel architecture," *IEEE Micro*, vol. 16, no. 4, pp. 42–50, 1996. [doi:10.1109/40.526924](https://doi.org/10.1109/40.526924). Packed (subword) SIMD.
5. S. K. Raman, V. Pentkovski and J. Keshava, "Implementing streaming SIMD extensions on the Pentium III processor," *IEEE Micro*, vol. 20, no. 4, pp. 47–57, 2000. [doi:10.1109/40.865866](https://doi.org/10.1109/40.865866). 128-bit SIMD registers.
6. C. E. Kozyrakis and D. A. Patterson, "Scalable vector processors for embedded systems," *IEEE Micro*, vol. 23, no. 6, pp. 36–45, 2003. [doi:10.1109/MM.2003.1261385](https://doi.org/10.1109/MM.2003.1261385). VIRAM; lanes scale more simply than superscalar or VLIW.
7. K. Asanović, "Vector microprocessors," Ph.D. dissertation, UC Berkeley, 1998.
8. Y. Lee *et al.*, "Exploring the tradeoffs between programmability and efficiency in data-parallel accelerators," *ISCA*, 2011, pp. 129–140. [PDF](https://www.csl.cornell.edu/~cbatten/pdfs/lee-maven-isca2011.pdf)
9. RISC-V International, "The RISC-V 'V' vector extension," v1.0, 2021. [Specification](https://docs.riscv.org/reference/isa/unpriv/v-st-ext.html)
10. M. Cavalcante *et al.*, "Ara: A 1-GHz+ scalable and energy-efficient RISC-V vector processor …," *IEEE TVLSI*, vol. 28, no. 2, pp. 530–543, 2020. [arXiv:1906.00478](https://arxiv.org/abs/1906.00478)

## Current SIMD instruction sets

11. Intel, *Intel 64 and IA-32 Architectures Software Developer's Manual*, vol. 2: SSE2 and AVX2 instructions such as `PMADDWD`. [intel.com/sdm](https://www.intel.com/sdm)
12. Arm, *Arm Architecture Reference Manual for A-profile Architecture*: Advanced SIMD (Neon), 32 × 128-bit registers, `ADDV`. [DDI 0487](https://developer.arm.com/documentation/ddi0487/latest)
13. MIPS Technologies, "MIPS SIMD Architecture," white paper, rev. 1.00, 2012: 32 × 128-bit registers, 8- to 64-bit elements. GCC's [MSA built-ins](https://gcc.gnu.org/onlinedocs/gcc/MIPS-SIMD-Architecture-_0028MSA_0029-Support.html) list the instructions, including `DOTP_S`.

## Soft vector processors on FPGAs

14. P. Yiannacouras, J. G. Steffan and J. Rose, "VESPA: Portable, scalable, and flexible FPGA-based vector processors," *CASES*, 2008, pp. 61–70. [PDF](https://www.eecg.utoronto.ca/~steffan/papers/cases08.pdf)
15. J. Yu, C. Eagleston, C. H.-Y. Chou, M. Perreault and G. Lemieux, "Vector processing as a soft processor accelerator," *ACM TRETS*, vol. 2, no. 2, 2009. [doi:10.1145/1534916.1534922](https://doi.org/10.1145/1534916.1534922)
16. C. H. Chou *et al.*, "VEGAS: Soft vector processor with scratchpad memory," *FPGA*, 2011, pp. 15–24. [PDF](https://people.ece.ubc.ca/lemieux/publications/chou-fpga2011.pdf)
17. A. Severance and G. G. F. Lemieux, "Embedded supercomputing in FPGAs with the VectorBlox MXP matrix processor," *CODES+ISSS*, 2013. [doi:10.1109/CODES-ISSS.2013.6658993](https://doi.org/10.1109/CODES-ISSS.2013.6658993)

## Performance and tools

18. G. M. Amdahl, "Validity of the single processor approach to achieving large scale computing capabilities," *AFIPS Spring Joint Computer Conf.*, 1967, pp. 483–485.
19. D. Shah *et al.*, "Yosys+nextpnr: An open source framework from Verilog to bitstream for commercial FPGAs," *FCCM*, 2019. [arXiv:1903.10407](https://arxiv.org/abs/1903.10407)
20. S. Williams, Icarus Verilog. [steveicarus.github.io/iverilog](https://steveicarus.github.io/iverilog/)
