--------------------------------------------------------------------------------
-- Register-level testbench for the custom AXI4-Lite IP  myAXI4lite_swled_v1_0
--
-- tb_axilite.vhd is the smoke test (one read, one write, "does the wiring work").
-- This testbench checks the BEHAVIOR of the register file, one test at a time:
--
--   Test 1  reset values           every register reads 0 after reset, LEDs are off
--   Test 2  switches (reg0)        reg0 follows sw_i live
--   Test 3  reg0 is read-only      a write to 0x0 is ignored and does not disturb other registers
--   Test 4  LEDs (reg1)            reg1 drives led_o, with several patterns, read back over AXI
--   Test 5  reg2 / reg3            registers hold their data and do not disturb each other
--   Test 6  walking ones on reg2   catches stuck or shorted data bits
--   Test 7  partial writes (WSTRB) only the enabled byte lanes change
--   Test 8  negative test          a deliberately wrong check, to prove the testbench CAN fail
--
-- REGISTER MAP (byte addresses, register is selected by address bits 3:2)
--   0x0  reg0  read-only   bits 7:0 = sw_i, bits 31:8 = 0
--   0x4  reg1  read/write  bits 7:0 drive led_o
--   0x8  reg2  read/write  plain storage
--   0xC  reg3  read/write  plain storage
--
-- HOW TO RUN (ModelSim)
--   * VHDL-2008. Compile order: myAXI4lite_swled_v1_0_S00_AXI.vhd,
--     myAXI4lite_swled_v1_0.vhd, then this file. uvvm_util must be mapped.
--   * Run with "run -all". Every test prints a header line, every bus transaction is
--     logged (ID_BFM) and so is every passed check_value (ID_POS_ACK), so a passing run is
--     visible in the transcript.
--   * The end of the transcript is the UVVM alert summary. Test 8 raises one error ON PURPOSE
--     and registers it as an expected alert, so a good run still ends with
--     "Simulation SUCCESS" and shows 1 expected ERROR.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library STD;
use std.env.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

use uvvm_util.axilite_bfm_pkg.all;

entity tb_axilite_regs is
end tb_axilite_regs;

architecture sim of tb_axilite_regs is

-- CONSTANTS
constant c_clkperiod                : time := 10 ns;      -- 100 MHz
constant c_clock_high_percentage    : integer := 50;
-- These two must match the generics of the IP.
constant c_axi_addr_width           : integer := 4;
constant c_axi_data_width           : integer := 32;
-- Byte addresses of the four registers.
constant c_reg0_addr                : unsigned (c_axi_addr_width-1 downto 0) := x"0";   -- switches (read-only)
constant c_reg1_addr                : unsigned (c_axi_addr_width-1 downto 0) := x"4";   -- LEDs (read/write)
constant c_reg2_addr                : unsigned (c_axi_addr_width-1 downto 0) := x"8";   -- storage
constant c_reg3_addr                : unsigned (c_axi_addr_width-1 downto 0) := x"C";   -- storage
-- Set to false to skip the deliberate failure in test 8.
constant c_run_negative_test        : boolean := true;

-- Byte enables for the partial writes of test 7. One bit per byte lane, bit 0 = bits 7:0 of the data.
constant c_be_none                  : std_logic_vector(3 downto 0) := "0000";   -- no byte lane enabled
constant c_be_byte1                 : std_logic_vector(3 downto 0) := "0010";   -- byte 1 only
constant c_be_bytes02               : std_logic_vector(3 downto 0) := "0101";   -- bytes 0 and 2

signal clk                  : std_logic := '0';
signal resetn               : std_logic := '0';   -- AXI reset is active LOW
signal sw_i                 : std_logic_vector (7 downto 0) := (others => '0');   -- switches, driven by this testbench
signal led_o                : std_logic_vector (7 downto 0);                      -- LEDs, driven by the IP

-- axilite_bfm signals (see tb_axilite.vhd for a longer explanation of this record)
-- The record bundles the five AXI-Lite channels; the vector widths are given here.
signal axilite_if           : t_axilite_if(
    write_address_channel(
        awaddr(c_axi_addr_width-1 downto 0)
        ),
    write_data_channel(
        wdata(c_axi_data_width-1 downto 0),
        wstrb(c_axi_data_width/8-1 downto 0)      -- one strobe bit per data byte
        ),
    read_address_channel(
        araddr(c_axi_addr_width-1 downto 0)
    ),
    read_data_channel(
        rdata(c_axi_data_width-1 downto 0)
    )
);
signal axilite_bfm_config   : t_axilite_bfm_config := C_AXILITE_BFM_CONFIG_DEFAULT;
-- Severity used by axilite_check on a mismatch.
signal alert_level          : t_alert_level := error;

begin

-----------------------------------------------------------------------------
-- DUT: the custom AXI4-Lite IP, connected to the fields of axilite_if.
-----------------------------------------------------------------------------
DUT : entity work.myAXI4lite_swled_v1_0
generic map(
C_S00_AXI_DATA_WIDTH    => c_axi_data_width,
C_S00_AXI_ADDR_WIDTH    => c_axi_addr_width
)
port map(
sw_i    => sw_i,
led_o   => led_o,
s00_axi_aclk    => clk,
s00_axi_aresetn => resetn,
-- AXI4 write address channel
s00_axi_awaddr  => axilite_if.write_address_channel.awaddr,
s00_axi_awprot  => axilite_if.write_address_channel.awprot,
s00_axi_awvalid => axilite_if.write_address_channel.awvalid,
s00_axi_awready => axilite_if.write_address_channel.awready,
-- AXI4 write data channel
s00_axi_wdata   => axilite_if.write_data_channel.wdata,
s00_axi_wstrb   => axilite_if.write_data_channel.wstrb,
s00_axi_wvalid  => axilite_if.write_data_channel.wvalid,
s00_axi_wready  => axilite_if.write_data_channel.wready,
-- AXI4 write response channel
s00_axi_bresp   => axilite_if.write_response_channel.bresp,
s00_axi_bvalid  => axilite_if.write_response_channel.bvalid,
s00_axi_bready  => axilite_if.write_response_channel.bready,
-- AXI4 read address channel
s00_axi_araddr  => axilite_if.read_address_channel.araddr,
s00_axi_arprot  => axilite_if.read_address_channel.arprot,
s00_axi_arvalid => axilite_if.read_address_channel.arvalid,
s00_axi_arready => axilite_if.read_address_channel.arready,
-- AXI4 read data channel
s00_axi_rdata   => axilite_if.read_data_channel.rdata,
s00_axi_rresp   => axilite_if.read_data_channel.rresp,
s00_axi_rvalid  => axilite_if.read_data_channel.rvalid,
s00_axi_rready  => axilite_if.read_data_channel.rready
);

-----------------------------------------------------------------------------
-- Clock generator (UVVM)
-----------------------------------------------------------------------------
clock_generator(clk, c_clkperiod, c_clock_high_percentage);

------------------------------------------------
-- PROCESS: p_main  (the test sequence)
------------------------------------------------
p_main: process
    constant C_SCOPE        : string    := C_TB_SCOPE_DEFAULT;
    variable v_data         : std_logic_vector(c_axi_data_width-1 downto 0);

    -- LED patterns for test 4: alternating bits, all ones, all zeros
    type t_pattern is array (0 to 3) of std_logic_vector(7 downto 0);
    constant c_led_patterns : t_pattern := (x"A5", x"5A", x"FF", x"00");

    -- Local wrappers around the BFM procedures: same name, fewer arguments (see tb_axilite.vhd).
    -- 1) full 32-bit write, all byte lanes enabled
    procedure axilite_write (
      constant addr_value : in unsigned;
      constant data_value : in std_logic_vector;
      constant msg        : in string) is
    begin
        axilite_write(addr_value, data_value, msg, clk, axilite_if,
                      C_SCOPE, shared_msg_id_panel, axilite_bfm_config);
    end;

    -- 2) partial write: only the byte lanes set in byte_enable are written (AXI WSTRB).
    --    This calls the BFM overload that has a byte_enable argument.
    procedure axilite_write (
      constant addr_value  : in unsigned;
      constant data_value  : in std_logic_vector;
      constant byte_enable : in std_logic_vector;
      constant msg         : in string) is
    begin
        axilite_write(addr_value, data_value, byte_enable, msg, clk, axilite_if,
                      C_SCOPE, shared_msg_id_panel, axilite_bfm_config);
    end;

    -- 3) read a register over the bus and compare with the expected value
    procedure axilite_check (
      constant addr_value : in unsigned;
      constant data_exp   : in std_logic_vector;
      constant msg        : in string) is
    begin
        axilite_check(addr_value, data_exp, msg, clk, axilite_if, alert_level,
                      C_SCOPE, shared_msg_id_panel, axilite_bfm_config);
    end;

begin

    -- The BFM needs the real clock period. It is a signal, so give it a moment to take effect.
    axilite_bfm_config.clock_period     <= c_clkperiod;
    wait for 1 ns;

    -- Log control: nothing, except test headers (ID_LOG_HDR), every bus transaction (ID_BFM)
    -- and every passed check_value (ID_POS_ACK). Without ID_POS_ACK the checks on the led_o pins
    -- pass silently: a failure would still be reported, but a pass would leave no line in the transcript.
    disable_log_msg(ALL_MESSAGES);
    enable_log_msg(ID_LOG_HDR);
    enable_log_msg(ID_BFM);
    enable_log_msg(ID_POS_ACK);
    -- By default UVVM stops the simulation at the first ERROR. 0 = never stop, keep running,
    -- so that all failures show up in one run. Test 8 needs this as well.
    set_alert_stop_limit(ERROR, 0);

    log(ID_LOG_HDR, "Start Simulation of register-level TB for custom axi lite IP", C_SCOPE);

    -- Reset: hold it low for 10 clocks, release, let the IP settle.
    resetn  <= '0';
    wait for c_clkperiod*10;
    resetn  <= '1';
    wait for c_clkperiod*10;

    -- Put the interface signals in their idle state before the first transaction.
    axilite_if <= init_axilite_if_signals(c_axi_addr_width,c_axi_data_width);
    wait for c_clkperiod;

    --==================================================================================================
    -- Test 1: reset values
    -- After reset reg1..reg3 must be 0 and the LEDs must be off. reg0 is not a register
    -- but the switch inputs, which are 0 at this point.
    --------------------------------------------------------------------------------------
    log(ID_LOG_HDR, "Test 1: reset values", C_SCOPE);
    axilite_check(c_reg0_addr, x"00000000", "reg0 = switches = 0 after start-up");
    axilite_check(c_reg1_addr, x"00000000", "reg1 is 0 after reset");
    axilite_check(c_reg2_addr, x"00000000", "reg2 is 0 after reset");
    axilite_check(c_reg3_addr, x"00000000", "reg3 is 0 after reset");
    check_value(led_o, x"00", ERROR, "led_o is 0 after reset", C_SCOPE);

    --==================================================================================================
    -- Test 2: switches through reg0
    -- sw_i is a plain input, reg0 must follow it. Two different values show that it is live
    -- and not captured once.
    --------------------------------------------------------------------------------------
    log(ID_LOG_HDR, "Test 2: reg0 follows the switches", C_SCOPE);
    sw_i    <= x"3C";
    wait for c_clkperiod*2;
    axilite_check(c_reg0_addr, x"0000003C", "reg0 reads sw_i = 0x3C");
    sw_i    <= x"A5";
    wait for c_clkperiod*2;
    axilite_check(c_reg0_addr, x"000000A5", "reg0 reads sw_i = 0xA5");

    --==================================================================================================
    -- Test 3: reg0 is read-only
    -- In the IP the write branch of register 0 is commented out. The write must be accepted by the bus
    -- (the BFM expects an OKAY response) but must change nothing: reg0 still shows the
    -- switches, and the write must not leak into reg1 (the LEDs).
    --------------------------------------------------------------------------------------
    log(ID_LOG_HDR, "Test 3: a write to reg0 is ignored", C_SCOPE);
    sw_i    <= x"55";
    wait for c_clkperiod*2;
    axilite_write(c_reg0_addr, x"FFFFFFFF", "write 0xFFFFFFFF to the read-only reg0");
    wait for c_clkperiod*2;
    axilite_check(c_reg0_addr, x"00000055", "reg0 still shows the switches (0x55)");
    axilite_check(c_reg1_addr, x"00000000", "reg1 not disturbed by the write to reg0");
    check_value(led_o, x"00", ERROR, "LEDs still off after the write to reg0", C_SCOPE);

    --==================================================================================================
    -- Test 4: LEDs through reg1
    -- Write several patterns. Each one is checked on the led_o pins (the real output) and
    -- by reading reg1 back over the bus. Only bits 7:0 of reg1 reach the pins.
    --------------------------------------------------------------------------------------
    log(ID_LOG_HDR, "Test 4: reg1 drives led_o", C_SCOPE);
    for i in c_led_patterns'range loop
        v_data  := x"000000" & c_led_patterns(i);
        axilite_write(c_reg1_addr, v_data, "write LED pattern " & integer'image(i));
        wait for c_clkperiod*2;
        check_value(led_o, c_led_patterns(i), ERROR, "led_o follows reg1, pattern " & integer'image(i), C_SCOPE);
        axilite_check(c_reg1_addr, v_data, "reg1 reads back pattern " & integer'image(i));
    end loop;

    --==================================================================================================
    -- Test 5: reg2 and reg3 hold their data and do not disturb each other
    -- Write all three writable registers with different values, then read everything back.
    -- This catches a wrong address decode (a write landing in the neighbouring register).
    --------------------------------------------------------------------------------------
    log(ID_LOG_HDR, "Test 5: registers are independent", C_SCOPE);
    axilite_write(c_reg1_addr, x"000000C1", "reg1 = 0xC1");
    axilite_write(c_reg2_addr, x"DEADBEEF", "reg2 = 0xDEADBEEF");
    axilite_write(c_reg3_addr, x"CAFEF00D", "reg3 = 0xCAFEF00D");
    wait for c_clkperiod*2;
    axilite_check(c_reg0_addr, x"00000055", "reg0 still the switches");
    axilite_check(c_reg1_addr, x"000000C1", "reg1 holds 0xC1");
    axilite_check(c_reg2_addr, x"DEADBEEF", "reg2 holds 0xDEADBEEF");
    axilite_check(c_reg3_addr, x"CAFEF00D", "reg3 holds 0xCAFEF00D");
    check_value(led_o, x"C1", ERROR, "led_o shows reg1 only, writes to reg2/reg3 do not touch it", C_SCOPE);

    --==================================================================================================
    -- Test 6: walking ones on reg2
    -- A single 1 moves through all 32 data bits. Every bit has to be stored and read back
    -- correctly. This finds bits that are stuck, shorted to a neighbour or missing.
    --------------------------------------------------------------------------------------
    log(ID_LOG_HDR, "Test 6: walking ones on reg2", C_SCOPE);
    for i in 0 to c_axi_data_width-1 loop
        v_data  := std_logic_vector(shift_left(to_unsigned(1, c_axi_data_width), i));
        axilite_write(c_reg2_addr, v_data, "walking one, bit " & integer'image(i));
        axilite_check(c_reg2_addr, v_data, "walking one read back, bit " & integer'image(i));
    end loop;
    -- the neighbour must have survived all of that
    axilite_check(c_reg3_addr, x"CAFEF00D", "reg3 untouched by the reg2 loop");

    --==================================================================================================
    -- Test 7: partial writes with the byte strobes (WSTRB)
    -- AXI lets the master write only some bytes of a 32-bit word. The IP must change only the
    -- enabled byte lanes and keep the others.
    --------------------------------------------------------------------------------------
    log(ID_LOG_HDR, "Test 7: partial writes (WSTRB)", C_SCOPE);
    -- reg2: byte lanes 0 and 2 get the new value, lanes 1 and 3 keep the old one
    --   old  0x11223344, new 0xAABBCCDD, enabled bytes 0 and 2  ->  0x11BB33DD
    axilite_write(c_reg2_addr, x"11223344", "reg2 = 0x11223344 (all bytes)");
    axilite_write(c_reg2_addr, x"AABBCCDD", c_be_bytes02, "write 0xAABBCCDD to bytes 0 and 2 of reg2");
    axilite_check(c_reg2_addr, x"11BB33DD", "only bytes 0 and 2 of reg2 changed");

    -- no byte lane enabled: the write is accepted but nothing may change
    axilite_write(c_reg2_addr, x"FFFFFFFF", c_be_none, "write 0xFFFFFFFF to reg2 with no byte enabled");
    axilite_check(c_reg2_addr, x"11BB33DD", "reg2 unchanged after a write with WSTRB = 0000");

    -- reg1: byte 1 does not reach the LED pins (only bits 7:0 do), but it is stored in the register
    axilite_write(c_reg1_addr, x"000000A5", "reg1 = 0xA5 (all bytes)");
    axilite_write(c_reg1_addr, x"0000FF00", c_be_byte1, "write 0xFF to byte 1 of reg1");
    wait for c_clkperiod*2;
    axilite_check(c_reg1_addr, x"0000FFA5", "byte 1 of reg1 changed, byte 0 kept");
    check_value(led_o, x"A5", ERROR, "led_o unchanged, it only follows byte 0", C_SCOPE);

    --==================================================================================================
    -- Test 8: negative test - make the testbench fail on purpose
    -- A testbench that cannot fail proves nothing. Here reg2 is checked against a WRONG value.
    -- The check raises an ERROR alert. increment_expected_alerts tells UVVM that exactly one
    -- ERROR is expected, so the final summary still says SUCCESS and lists 1 expected ERROR.
    -- To see what a real failure looks like, delete the increment_expected_alerts line: the same
    -- run then ends with "Simulation FAILED".
    --------------------------------------------------------------------------------------
    if c_run_negative_test then
        log(ID_LOG_HDR, "Test 8: deliberate failure (one expected ERROR)", C_SCOPE);
        increment_expected_alerts(ERROR, 1, "the next check is wrong on purpose", C_SCOPE);
        axilite_check(c_reg2_addr, x"00000000", "WRONG on purpose: reg2 is 0x11BB33DD, not 0");
    end if;

    --==================================================================================================
    -- Ending the simulation
    --------------------------------------------------------------------------------------
    wait for 1000 ns;             -- to allow some time for completion
    report_alert_counters(FINAL); -- Report final counters and print conclusion for simulation (Success/Fail)
    log(ID_LOG_HDR, "SIMULATION COMPLETED", C_SCOPE);

    -- Finish the simulation
    std.env.stop;
    wait;  -- to stop completely

end process p_main;

end architecture;
