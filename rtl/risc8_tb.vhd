--------------------------------------------------------------------------------
-- Testbench for risc8_cpu (runs in ISim or GHDL)
-- DIV_BITS = 1 makes the CPU step every 2 clocks instead of every 2^25.
-- Checks that the LEDs show 10, 30, 60, 100 in order and then hold 100.
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity risc8_tb is
end risc8_tb;

architecture sim of risc8_tb is

    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal out_bus : std_logic_vector(7 downto 0);
    signal done    : boolean := false;

    type exp_t is array (0 to 3) of integer;
    constant EXPECTED : exp_t := (10, 30, 60, 100);

begin

    uut : entity work.risc8_cpu
        generic map (DIV_BITS => 1)
        port map (clk => clk, rst => rst, out_bus => out_bus);

    clk <= not clk after 5 ns when not done else '0';

    process
        variable idx  : integer := 0;
        variable prev : std_logic_vector(7 downto 0) := (others => '0');
        variable errs : integer := 0;
    begin
        rst <= '1';
        wait for 50 ns;
        wait until rising_edge(clk);
        rst <= '0';

        -- Run long enough for the whole program (about 40 instructions)
        for cycle in 1 to 200 loop
            wait until rising_edge(clk);
            if out_bus /= prev then
                report "LEDs = " & integer'image(to_integer(unsigned(out_bus)));
                if idx > 3 then
                    report "Unexpected extra LED update" severity error;
                    errs := errs + 1;
                elsif to_integer(unsigned(out_bus)) /= EXPECTED(idx) then
                    report "Expected " & integer'image(EXPECTED(idx)) severity error;
                    errs := errs + 1;
                end if;
                idx  := idx + 1;
                prev := out_bus;
            end if;
        end loop;

        if idx /= 4 then
            report "Expected 4 LED updates, saw " & integer'image(idx) severity error;
            errs := errs + 1;
        end if;

        if errs = 0 then
            report "TEST PASSED: final LEDs = " & integer'image(to_integer(unsigned(out_bus)));
        else
            report "TEST FAILED with " & integer'image(errs) & " error(s)" severity error;
        end if;

        done <= true;
        wait;
    end process;

end sim;
