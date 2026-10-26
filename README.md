# RISC-8

A minimal single-cycle 8-bit RISC CPU in VHDL for the Digilent **Nexys 3** (Spartan-6, Xilinx ISE 14.7).

## What makes it RISC

| | μCPU-8 (microcoded) | RISC-8 |
| :--- | :--- | :--- |
| Control | 32-step microcode ROM | Hardwired decoder (one `case` on the opcode) |
| Clocks per instruction | 4–8 | **1** |
| Registers | One accumulator | **8 registers**, R0 always 0 |
| Instruction length | 1 or 2 bytes | **Fixed 16 bits**, fields always in the same place |
| Memory access | ALU reads memory directly | **Load/store only**: the ALU works on registers |
| Memories | One RAM for code and data | **Separate** instruction ROM and data RAM (Harvard) |
| Datapath | Shared bus | Dedicated paths, two register read ports |
| I/O | ACC wired to LEDs | **Memory-mapped**: store to address `0xFF` |
| Halt | Special microcode loop | No HALT instruction: a branch to itself |

## Files

| File | Description |
| :--- | :--- |
| `risc8_cpu.vhd` | ISA package (opcodes and assembler functions) and the CPU |
| `risc8_tb.vhd` | Self-checking testbench (ISim or GHDL) |
| `nexys3.ucf` | Pin and timing constraints for the Nexys 3 |

## Datapath

```text
           +-----+      +---------+   instr   +----------+   control
   +------>| PC  |----->|  IMEM   |---------->| Decoder  |----------> (all blocks)
   |       +-----+      | 32 x 16 |     |     +----------+
   |                    +---------+     |
   |                                    | fields A, B, C, imm6
   |                                    v
   |            +-------------------------------+
   |            |   Register file  R0..R7       |
   |            |   read B -> rd1               |<---------------------+
   |            |   read C or A -> rd2          |  write A <- wb_data  |
   |            +-------------------------------+                      |
   |                 | rd1          | rd2                              |
   |                 |              +----+---------------+             |
   |                 v              v    | imm (sign-ext)|             |
   |            +--------------------+   |               |             |
   |            |        ALU         |<--+               | SW data     |
   |            +--------------------+                   v             |
   |                     | alu_y (result / address) +---------+        |
   |                     +------------------------->|  DMEM   |        |
   |                     |                          | 16 x 8  |        |
   |                     |                          | + 0xFF  |--> LEDs|
   |                     |                          +---------+        |
   |                     |                               | mem data    |
   |                     +-------------------------> [ write-back ] ---+
   |
   +---- next PC: PC+1, PC+1+imm (taken branch), or addr8 (JMP)
```

## Instruction set

### Formats (16 bits)

```text
         15    12 11   9 8    6 5    3 2    0
R-type  | 0000   |  A=rd | B=rs | C=rt | funct |
I-type  | opcode |   A   |  B   |  imm6 (signed) |
J-type  | 0110   |  0000    |    addr8         |
                  (11..8)       (7..0)
```

Register port 1 always reads field B. Port 2 reads field C for R-type and field A otherwise. Because the fields never move, decoding is just wiring.

### Instructions

| Opcode | Instruction | Operation |
| :--- | :--- | :--- |
| `0000` | `ADD/SUB/AND/OR/XOR rd, rs, rt` | `rd ← rs op rt` (funct `000`–`100`) |
| `0000` | `SLT rd, rs, rt` | `rd ← 1 if rs < rt (signed) else 0` (funct `101`) |
| `0000` | `SHL/SHR rd, rs, rt` | `rd ← rs << rt[2:0]` / `>>` (funct `110`/`111`) |
| `0001` | `ADDI rd, rs, imm` | `rd ← rs + imm` |
| `0010` | `LW rd, imm(rs)` | `rd ← mem[rs + imm]` |
| `0011` | `SW rt, imm(rs)` | `mem[rs + imm] ← rt` |
| `0100` | `BEQ ra, rb, off` | if `ra = rb`: `PC ← PC + 1 + off` |
| `0101` | `BNE ra, rb, off` | if `ra ≠ rb`: `PC ← PC + 1 + off` |
| `0110` | `JMP addr` | `PC ← addr` |

Unused opcodes do nothing. `0x0000` (`ADD R0,R0,R0`) is the NOP. Common idioms built from these: `ADDI rd, R0, k` loads a constant, `ADD rd, rs, R0` copies a register, and `BEQ R0, R0, -1` halts.

### Memory map (data side)

| Address | Contents |
| :--- | :--- |
| `0x00`–`0x0F` | 16 bytes of data RAM (addresses wrap every 16) |
| `0xFF` | LED register: `SW` writes the LEDs, `LW` reads them back |

## Demo program

The program in `IMEM` sums four bytes stored in data RAM:

```asm
        ADDI R1, R0, 0      ; pointer
        ADDI R2, R0, 4      ; count
        ADDI R3, R0, 0      ; sum
loop:   LW   R4, 0(R1)
        ADD  R3, R3, R4
        SW   R3, -1(R0)     ; LEDs = running sum (address 0xFF)
        ADDI R1, R1, 1
        ADDI R2, R2, -1
        BNE  R2, R0, loop
        SW   R3, 4(R0)      ; mem[4] = sum
halt:   BEQ  R0, R0, halt
```

Data RAM holds 10, 20, 30, 40, so the LEDs show **10 → 30 → 60 → 100** (`01100100`).

### Writing your own program

Instructions are written with VHDL functions from `risc8_pkg`, so no hand-encoded bits are needed:

```vhdl
3 => I_LW (4, 0, 1),     -- LW  R4, 0(R1)
8 => I_BNE(2, 0, -6),    -- BNE R2, R0, -6
```

Branch offsets are relative to the next instruction: `off = target − (address + 1)`.

## Building with ISE 14.7

1. New project: family `Spartan6`, device `XC6SLX16`, package `CSG324`, speed `-3`, preferred language VHDL.
2. Add `risc8_cpu.vhd` and `nexys3.ucf`. Set `risc8_cpu` as the top module.
3. Run **Generate Programming File** and program the board with iMPACT or Adept.

## Simulation

Add `risc8_tb.vhd` as a simulation source, set `risc8_tb` as the top module in the Simulation view, and run ISim for 2 µs. The testbench sets `DIV_BITS => 1`, so the CPU steps every 2 clocks, and it checks the LED sequence automatically. The console should end with `TEST PASSED: final LEDs = 100`.

With GHDL:

```sh
ghdl -a risc8_cpu.vhd risc8_tb.vhd
ghdl -e risc8_tb
ghdl -r risc8_tb
```

## On the board

Press **BTNS** to reset. The LEDs go dark, then show 10, 30, 60 and 100, about 2 seconds apart, and stay at 100. Press BTNS again to rerun.

## Ideas for next steps

- Map the 8 slide switches to a load address (for example `0xFE`) for input.
- Add `JAL`/`JR` for subroutine calls.
- Split into a 5-stage pipeline (IF, ID, EX, MEM, WB) with forwarding and hazard detection.

## Author

MSc. Eng. Erick Poppe
