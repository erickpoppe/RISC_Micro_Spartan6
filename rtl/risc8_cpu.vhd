--------------------------------------------------------------------------------
-- RISC-8: a minimal single-cycle 8-bit RISC CPU for the Digilent Nexys 3
--
-- RISC characteristics shown by this design:
--   * Fixed-length 16-bit instructions with register fields in fixed places
--   * Load/store architecture: only LW/SW touch memory, the ALU works on
--     registers (or a small immediate)
--   * 8 general-purpose registers, R0 hard-wired to zero
--   * Hardwired (combinational) decoder, no microcode
--   * One instruction per clock (single cycle)
--   * Separate instruction and data memories (Harvard)
--   * Memory-mapped I/O: storing to address 0xFF drives the LEDs
--
-- Toolchain: Xilinx ISE 14.7 (XST), device XC6SLX16-3CSG324
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package risc8_pkg is

    subtype word16 is std_logic_vector(15 downto 0);

    -- Opcodes (instr(15 downto 12))
    constant OP_RTYPE : std_logic_vector(3 downto 0) := "0000";
    constant OP_ADDI  : std_logic_vector(3 downto 0) := "0001";
    constant OP_LW    : std_logic_vector(3 downto 0) := "0010";
    constant OP_SW    : std_logic_vector(3 downto 0) := "0011";
    constant OP_BEQ   : std_logic_vector(3 downto 0) := "0100";
    constant OP_BNE   : std_logic_vector(3 downto 0) := "0101";
    constant OP_JMP   : std_logic_vector(3 downto 0) := "0110";

    -- ALU functions (R-type funct field, instr(2 downto 0))
    constant FN_ADD : std_logic_vector(2 downto 0) := "000";
    constant FN_SUB : std_logic_vector(2 downto 0) := "001";
    constant FN_AND : std_logic_vector(2 downto 0) := "010";
    constant FN_OR  : std_logic_vector(2 downto 0) := "011";
    constant FN_XOR : std_logic_vector(2 downto 0) := "100";
    constant FN_SLT : std_logic_vector(2 downto 0) := "101";
    constant FN_SHL : std_logic_vector(2 downto 0) := "110";
    constant FN_SHR : std_logic_vector(2 downto 0) := "111";

    -- Small "assembler": build instruction words from readable arguments.
    -- Register arguments are 0..7, immediates are signed -32..31.
    function I_ADD  (rd, rs, rt : integer) return word16;
    function I_SUB  (rd, rs, rt : integer) return word16;
    function I_AND  (rd, rs, rt : integer) return word16;
    function I_OR   (rd, rs, rt : integer) return word16;
    function I_XOR  (rd, rs, rt : integer) return word16;
    function I_SLT  (rd, rs, rt : integer) return word16;
    function I_SHL  (rd, rs, rt : integer) return word16;
    function I_SHR  (rd, rs, rt : integer) return word16;
    function I_ADDI (rd, rs, imm : integer) return word16;
    function I_LW   (rd, imm, rs : integer) return word16;   -- rd <- mem[rs+imm]
    function I_SW   (rt, imm, rs : integer) return word16;   -- mem[rs+imm] <- rt
    function I_BEQ  (ra, rb, off : integer) return word16;   -- if ra=rb: pc <- pc+1+off
    function I_BNE  (ra, rb, off : integer) return word16;
    function I_JMP  (addr : integer) return word16;
    constant I_NOP : word16 := x"0000";                     -- ADD R0,R0,R0

end package risc8_pkg;

package body risc8_pkg is

    function r3 (n : integer) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(n, 3));
    end function;

    function rtype (fn : std_logic_vector(2 downto 0); rd, rs, rt : integer) return word16 is
    begin
        return OP_RTYPE & r3(rd) & r3(rs) & r3(rt) & fn;
    end function;

    function itype (op : std_logic_vector(3 downto 0); a, b, imm : integer) return word16 is
    begin
        return op & r3(a) & r3(b) & std_logic_vector(to_signed(imm, 6));
    end function;

    function I_ADD (rd, rs, rt : integer) return word16 is begin return rtype(FN_ADD, rd, rs, rt); end function;
    function I_SUB (rd, rs, rt : integer) return word16 is begin return rtype(FN_SUB, rd, rs, rt); end function;
    function I_AND (rd, rs, rt : integer) return word16 is begin return rtype(FN_AND, rd, rs, rt); end function;
    function I_OR  (rd, rs, rt : integer) return word16 is begin return rtype(FN_OR,  rd, rs, rt); end function;
    function I_XOR (rd, rs, rt : integer) return word16 is begin return rtype(FN_XOR, rd, rs, rt); end function;
    function I_SLT (rd, rs, rt : integer) return word16 is begin return rtype(FN_SLT, rd, rs, rt); end function;
    function I_SHL (rd, rs, rt : integer) return word16 is begin return rtype(FN_SHL, rd, rs, rt); end function;
    function I_SHR (rd, rs, rt : integer) return word16 is begin return rtype(FN_SHR, rd, rs, rt); end function;

    function I_ADDI (rd, rs, imm : integer) return word16 is begin return itype(OP_ADDI, rd, rs, imm); end function;
    function I_LW   (rd, imm, rs : integer) return word16 is begin return itype(OP_LW,   rd, rs, imm); end function;
    function I_SW   (rt, imm, rs : integer) return word16 is begin return itype(OP_SW,   rt, rs, imm); end function;
    function I_BEQ  (ra, rb, off : integer) return word16 is begin return itype(OP_BEQ,  ra, rb, off); end function;
    function I_BNE  (ra, rb, off : integer) return word16 is begin return itype(OP_BNE,  ra, rb, off); end function;

    function I_JMP (addr : integer) return word16 is
    begin
        return OP_JMP & "0000" & std_logic_vector(to_unsigned(addr, 8));
    end function;

end package body risc8_pkg;

--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.risc8_pkg.all;

entity risc8_cpu is
    Generic (
        DIV_BITS : integer := 25   -- CPU steps once every 2^DIV_BITS clocks (~3 Hz)
    );
    Port (
        clk     : in  STD_LOGIC;   -- 100 MHz oscillator (V10)
        rst     : in  STD_LOGIC;   -- BTNS (B8), active high
        out_bus : out STD_LOGIC_VECTOR(7 downto 0)   -- LD7..LD0
    );
end risc8_cpu;

architecture rtl of risc8_cpu is

    ------------------------------------------------------------------------
    -- Instruction memory (ROM, 32 x 16).  Demo: sum the 4 bytes at data
    -- addresses 0..3, show the running total on the LEDs, store the result
    -- at address 4, then halt.
    ------------------------------------------------------------------------
    type imem_t is array (0 to 31) of word16;
    constant IMEM : imem_t := (
        0  => I_ADDI(1, 0, 0),     --        ADDI R1, R0, 0     ; R1 = pointer
        1  => I_ADDI(2, 0, 4),     --        ADDI R2, R0, 4     ; R2 = count
        2  => I_ADDI(3, 0, 0),     --        ADDI R3, R0, 0     ; R3 = sum
        3  => I_LW  (4, 0, 1),     -- loop:  LW   R4, 0(R1)     ; R4 = mem[R1]
        4  => I_ADD (3, 3, 4),     --        ADD  R3, R3, R4
        5  => I_SW  (3, -1, 0),    --        SW   R3, -1(R0)    ; LEDs = sum (addr 0xFF)
        6  => I_ADDI(1, 1, 1),     --        ADDI R1, R1, 1
        7  => I_ADDI(2, 2, -1),    --        ADDI R2, R2, -1
        8  => I_BNE (2, 0, -6),    --        BNE  R2, R0, loop  ; 8+1-6 = 3
        9  => I_SW  (3, 4, 0),     --        SW   R3, 4(R0)     ; mem[4] = sum
        10 => I_BEQ (0, 0, -1),    -- halt:  BEQ  R0, R0, halt  ; branch to itself
        others => I_NOP
    );

    -- Data memory (RAM, 16 x 8)
    type dmem_t is array (0 to 15) of std_logic_vector(7 downto 0);
    signal DMEM : dmem_t := (
        0 => x"0A",   -- 10
        1 => x"14",   -- 20
        2 => x"1E",   -- 30
        3 => x"28",   -- 40
        others => x"00"
    );

    constant IO_LED_ADDR : unsigned(7 downto 0) := x"FF";

    -- Register file (R0 is never written, so it always reads 0)
    type regfile_t is array (0 to 7) of std_logic_vector(7 downto 0);
    signal REGS : regfile_t := (others => (others => '0'));

    -- Clock enable and reset synchronizer
    signal clk_div  : unsigned(DIV_BITS-1 downto 0) := (others => '0');
    signal tick     : std_logic;
    signal rst_meta : std_logic := '1';
    signal rst_sync : std_logic := '1';

    -- State
    signal pc      : unsigned(7 downto 0) := (others => '0');
    signal led_reg : std_logic_vector(7 downto 0) := (others => '0');

    -- Fetch / decode
    signal instr   : word16;
    signal opcode  : std_logic_vector(3 downto 0);
    signal fa, fb, fc : integer range 0 to 7;   -- register fields A, B, C
    signal funct   : std_logic_vector(2 downto 0);
    signal imm_ext : unsigned(7 downto 0);      -- sign-extended 6-bit immediate

    -- Control signals (hardwired decoder outputs)
    signal reg_write, alu_src_imm, mem_to_reg, mem_write : std_logic;
    signal is_beq, is_bne, is_jmp : std_logic;
    signal alu_fn : std_logic_vector(2 downto 0);

    -- Datapath
    signal rd2_addr   : integer range 0 to 7;
    signal rd1, rd2   : std_logic_vector(7 downto 0);
    signal alu_a, alu_b, alu_y : unsigned(7 downto 0);
    signal mem_rdata  : std_logic_vector(7 downto 0);
    signal wb_data    : std_logic_vector(7 downto 0);
    signal pc_plus1, pc_next : unsigned(7 downto 0);
    signal take_branch : std_logic;

begin

    ------------------------------------------------------------------------
    -- Clock enable (~3 Hz with DIV_BITS = 25) and synchronized reset
    ------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            clk_div  <= clk_div + 1;
            rst_meta <= rst;
            rst_sync <= rst_meta;
        end if;
    end process;
    tick <= '1' when clk_div = (clk_div'range => '1') else '0';

    ------------------------------------------------------------------------
    -- Fetch
    ------------------------------------------------------------------------
    instr <= IMEM(to_integer(pc(4 downto 0)));

    ------------------------------------------------------------------------
    -- Decode: fixed fields
    --   R-type : op | A=rd | B=rs | C=rt | funct
    --   I-type : op | A    | B    | imm6
    --   J-type : op | 0000 | addr8
    ------------------------------------------------------------------------
    opcode  <= instr(15 downto 12);
    fa      <= to_integer(unsigned(instr(11 downto 9)));
    fb      <= to_integer(unsigned(instr(8 downto 6)));
    fc      <= to_integer(unsigned(instr(5 downto 3)));
    funct   <= instr(2 downto 0);
    imm_ext <= unsigned(resize(signed(instr(5 downto 0)), 8));

    -- Hardwired control: one row per opcode
    process(opcode, funct)
    begin
        reg_write   <= '0';
        alu_src_imm <= '0';
        mem_to_reg  <= '0';
        mem_write   <= '0';
        is_beq      <= '0';
        is_bne      <= '0';
        is_jmp      <= '0';
        alu_fn      <= FN_ADD;

        case opcode is
            when OP_RTYPE => reg_write <= '1'; alu_fn <= funct;
            when OP_ADDI  => reg_write <= '1'; alu_src_imm <= '1';
            when OP_LW    => reg_write <= '1'; alu_src_imm <= '1'; mem_to_reg <= '1';
            when OP_SW    => mem_write <= '1'; alu_src_imm <= '1';
            when OP_BEQ   => is_beq <= '1';
            when OP_BNE   => is_bne <= '1';
            when OP_JMP   => is_jmp <= '1';
            when others   => null;                 -- unused opcodes act as NOP
        end case;
    end process;

    ------------------------------------------------------------------------
    -- Register file: two read ports, one write port
    --   port 1 always reads field B
    --   port 2 reads field C for R-type, field A otherwise (SW data, BEQ/BNE)
    ------------------------------------------------------------------------
    rd2_addr <= fc when opcode = OP_RTYPE else fa;
    rd1 <= REGS(fb);
    rd2 <= REGS(rd2_addr);

    ------------------------------------------------------------------------
    -- ALU
    ------------------------------------------------------------------------
    alu_a <= unsigned(rd1);
    alu_b <= imm_ext when alu_src_imm = '1' else unsigned(rd2);

    process(alu_fn, alu_a, alu_b)
    begin
        case alu_fn is
            when FN_ADD => alu_y <= alu_a + alu_b;
            when FN_SUB => alu_y <= alu_a - alu_b;
            when FN_AND => alu_y <= alu_a and alu_b;
            when FN_OR  => alu_y <= alu_a or  alu_b;
            when FN_XOR => alu_y <= alu_a xor alu_b;
            when FN_SLT =>
                if signed(alu_a) < signed(alu_b) then
                    alu_y <= to_unsigned(1, 8);
                else
                    alu_y <= to_unsigned(0, 8);
                end if;
            when FN_SHL => alu_y <= shift_left (alu_a, to_integer(alu_b(2 downto 0)));
            when others => alu_y <= shift_right(alu_a, to_integer(alu_b(2 downto 0)));
        end case;
    end process;

    ------------------------------------------------------------------------
    -- Data memory read (address = ALU result) and write-back mux
    ------------------------------------------------------------------------
    mem_rdata <= led_reg when alu_y = IO_LED_ADDR
                 else DMEM(to_integer(alu_y(3 downto 0)));

    wb_data <= mem_rdata when mem_to_reg = '1' else std_logic_vector(alu_y);

    ------------------------------------------------------------------------
    -- Next PC
    ------------------------------------------------------------------------
    pc_plus1 <= pc + 1;

    take_branch <= '1' when (is_beq = '1' and rd1 =  rd2) or
                            (is_bne = '1' and rd1 /= rd2) else '0';

    pc_next <= unsigned(instr(7 downto 0)) when is_jmp = '1' else
               pc_plus1 + imm_ext          when take_branch = '1' else
               pc_plus1;

    ------------------------------------------------------------------------
    -- State update: one instruction per tick
    ------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_sync = '1' then
                pc      <= (others => '0');
                led_reg <= (others => '0');
            elsif tick = '1' then
                pc <= pc_next;

                if mem_write = '1' then
                    if alu_y = IO_LED_ADDR then
                        led_reg <= rd2;
                    else
                        DMEM(to_integer(alu_y(3 downto 0))) <= rd2;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Register file write (kept in its own process so XST infers LUT RAM)
    process(clk)
    begin
        if rising_edge(clk) then
            if tick = '1' and rst_sync = '0' and reg_write = '1' and fa /= 0 then
                REGS(fa) <= wb_data;
            end if;
        end if;
    end process;

    out_bus <= led_reg;

end rtl;
