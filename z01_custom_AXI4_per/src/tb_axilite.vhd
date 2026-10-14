--------------------------------------------------------------------------------
-- Testbench for the custom AXI4-Lite IP  myAXI4lite_swled_v1_0
--
-- WHAT THE IP DOES
--   An AXI4-Lite slave with four 32-bit registers. The address bus is 4 bits wide
--   and the register is selected by awaddr/araddr bits 3:2, so the byte addresses are:
--
--     0x0  reg0  read-only   bits 7:0 = sw_i (the switches), bits 31:8 = 0
--                            (writes to it are accepted but ignored)
--     0x4  reg1  read/write  bits 7:0 drive led_o
--     0x8  reg2  read/write  plain storage, no output pin
--     0xC  reg3  read/write  plain storage, no output pin
--
--   This testbench only uses reg0 and reg1 so far.
--
-- HOW THE VERIFICATION WORKS
--   The UVVM AXI-Lite BFM (bus functional model) plays the AXI MASTER, the IP is
--   the slave. One call such as axilite_write(...) runs a complete bus transaction:
--   it drives the address/data channels, waits for the slave's ready/valid
--   handshakes, takes the write response, and logs the result. Without a BFM you
--   would drive every AXI signal by hand and count clock cycles yourself.
--
--   p_main is the "sequencer": it only says WHAT to do (write this, expect that).
--   The BFM takes care of HOW the bus does it.
--
--   Two kinds of checks are used below:
--     axilite_check  read a register over the bus and compare it with an expected value
--     check_value    look at a plain signal (here the led_o pin) directly
--
-- HOW TO RUN (ModelSim)
--   * Compile as VHDL-2008 (the BFM uses records with unconstrained elements).
--   * Compile order: myAXI4lite_swled_v1_0_S00_AXI.vhd, myAXI4lite_swled_v1_0.vhd,
--     then this file.
--   * The library uvvm_util must be mapped to the compiled UVVM Light.
--   * Run with "run -all". The last lines of the transcript show the UVVM alert
--     summary: no ERROR or FAILURE alerts means the test passed.
--
-- REFERENCE
--   Mehmet Burak Aykenar, "Verification of a custom AXI4-Lite IP using UVVM"
--   (the structure of this testbench follows his article).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library STD;
use std.env.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;       -- UVVM utility library: log, alert, check_value, clock_generator, ...

use uvvm_util.axilite_bfm_pkg.all;         -- the AXI-Lite BFM (part of the uvvm_util library in UVVM Light)

use std.textio.all;
use std.env.finish;

entity tb_axilite is
end tb_axilite;

architecture sim of tb_axilite is

-- CONSTANTS
constant c_clkperiod                : time := 10 ns;      -- 100 MHz
constant c_clkfreq                  : integer := 100_000_000;
constant c_clock_high_percentage    : integer := 50;      -- clock duty cycle in percent
-- These two must match the generics of the IP (C_S00_AXI_ADDR_WIDTH / C_S00_AXI_DATA_WIDTH).
-- A mismatch gives width errors at elaboration, not a bus error at run time.
constant c_axi_addr_width           : integer := 4;
constant c_axi_data_width           : integer := 32;
-- Register addresses are BYTE addresses: one 32-bit register every 4 bytes.
-- They are unsigned vectors because that is the type the BFM procedures expect.
constant c_reg0_addr                : unsigned (c_axi_addr_width-1 downto 0) := x"0";   -- switches (read-only)
constant c_reg1_addr                : unsigned (c_axi_addr_width-1 downto 0) := x"4";   -- LEDs (read/write)

signal clk                  : std_logic := '0';
signal resetn               : std_logic := '0';   -- AXI reset is active LOW
signal sw_i                 : std_logic_vector (7 downto 0) := (others => '0');   -- switches, driven by this testbench
signal led_o                : std_logic_vector (7 downto 0);                      -- LEDs, driven by the IP

-- axilite_bfm signals
-- t_axilite_if is a record that bundles all five AXI-Lite channels:
-- write address (aw*), write data (w*), write response (b*), read address (ar*), read data (r*).
-- Some of its elements are vectors of unspecified length, so their widths have to be
-- given when the signal is declared (VHDL-2008 constrained record):
--   awaddr/araddr = address width, wdata/rdata = data width, wstrb = one bit per data byte.
-- The BFM drives the master-side wires (valid, address, data, strobes, bready, rready)
-- and reads the slave-side wires (ready, bvalid, bresp, rvalid, rdata, rresp).
-- The DUT port map below connects each DUT port to one field of this record.
signal axilite_if           : t_axilite_if(
    write_address_channel(
        awaddr(c_axi_addr_width-1 downto 0)
        ),
    write_data_channel(
        wdata(c_axi_data_width-1 downto 0),
        wstrb(4-1 downto 0)                       -- = c_axi_data_width/8 byte strobes
        ),
    read_address_channel(
        araddr(c_axi_addr_width-1 downto 0)
    ),
    read_data_channel(
        rdata(c_axi_data_width-1 downto 0)
    )
);
-- BFM settings (timeouts, expected response, protection bits, ...).
-- C_AXILITE_BFM_CONFIG_DEFAULT gives sensible defaults, for example:
--   max_wait_cycles = 1000      the BFM raises an alert if the slave never gives ready/valid
--   expected_response = OKAY    a different bresp/rresp (for example SLVERR) raises an alert
-- To test an error response on purpose, set expected_response in p_main first.
signal axilite_bfm_config   : t_axilite_bfm_config := C_AXILITE_BFM_CONFIG_DEFAULT;
-- Severity used when axilite_check finds a mismatch. "error" counts in the final alert summary.
signal alert_level : t_alert_level := error;

begin

-----------------------------------------------------------------------------
-- DUT: the custom AXI4-Lite IP.
-- Left side = DUT port, right side = the matching field of axilite_if.
-- awprot/arprot (protection bits) are driven by the BFM too, the IP does not use them.
-----------------------------------------------------------------------------
DUT : entity work.myAXI4lite_swled_v1_0
generic map(
-- Parameters of Axi Slave Bus Interface S00_AXI
C_S00_AXI_DATA_WIDTH    => c_axi_data_width,
C_S00_AXI_ADDR_WIDTH    => c_axi_addr_width
)
port map(
-- Users to add ports here
sw_i    => sw_i,
led_o   => led_o,
-- Ports of Axi Slave Bus Interface S00_AXI
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
-- Clock Generator (UVVM). A concurrent procedure call: it runs for the whole
-- simulation and toggles clk with the given period and duty cycle.
-----------------------------------------------------------------------------
clock_generator(clk, c_clkperiod, c_clock_high_percentage);

------------------------------------------------
-- PROCESS: p_main  (the test sequence)
------------------------------------------------
p_main: process
    constant C_SCOPE        : string    := C_TB_SCOPE_DEFAULT;    -- name shown in the UVVM log lines
    variable v_time_stamp   : time      := 0 ns;                  -- not used yet, handy for timing measurements
    variable v_data         : std_logic_vector(c_axi_data_width-1 downto 0);
    variable v_addr         : unsigned(c_axi_addr_width- 1 downto 0);

    -- Local wrappers around the BFM procedures.
    -- The BFM procedures take many arguments (clock, interface signal, scope,
    -- message panel, config) that are the same on every call. These local
    -- procedures have the same name but only take the three arguments that change,
    -- so the test below reads: axilite_write(address, data, "message").
    -- VHDL picks the right version by the number and types of the arguments:
    -- 3 arguments = this local wrapper, the long argument list = the BFM in the package.
    -- They are declared here, inside the process, because they use the signals
    -- clk, axilite_if and axilite_bfm_config, which have to be visible to the call.
    procedure axilite_write (
      constant addr_value : in unsigned;
      constant data_value : in std_logic_vector;
      constant msg        : in string) is
    begin

    axilite_write(
        addr_value,             -- keep as is
        data_value,             -- keep as is
        msg,                    -- keep as is
        clk,                    -- Clock signal
        axilite_if,             -- Signal must be visible in local process scope
        C_SCOPE,                -- Just use the default
        shared_msg_id_panel,    -- Use global, shared msg_id_panel
        axilite_bfm_config      -- Use locally defined configuration or C_AXILITE_BFM_CONFIG_DEFAULT
    );
    -- This version writes with all byte strobes set (wstrb = "1111") and
    -- protection "unprivileged, non-secure, data access". The BFM also has an overload with a
    -- byte_enable argument for partial writes.

    end;

    -- Same idea for reading: axilite_check reads the register over the bus and compares
    -- it with data_exp. A mismatch raises an alert with the severity in alert_level.
    -- The matching log line (ID_BFM) shows the address, the value read and the message.
    -- To just get the value without comparing, use axilite_read, which has a variable
    -- out argument for the data.
    procedure axilite_check (
      constant addr_value : in unsigned;
      constant data_exp   : in std_logic_vector;
      constant msg        : in string) is
    begin

        axilite_check(
            addr_value,             -- keep as is
            data_exp,               -- keep as is
            msg,                    -- keep as is
            clk,                    -- Clock signal
            axilite_if,             -- Signal must be visible in local process scope
            alert_level,            -- alert level
            C_SCOPE,                -- Just use the default
            shared_msg_id_panel,    -- Use global, shared msg_id_panel
            axilite_bfm_config      -- Use locally defined configuration or C_AXILITE_BFM_CONFIG_DEFAULT
        );
    end;

begin

    -- axi lite initializations
    -- The BFM needs to know the real clock period. It is a signal, so the new value only
    -- takes effect after a delta cycle: the short wait lets it settle before the first BFM call.
    axilite_bfm_config.clock_period     <= c_clkperiod;
    wait for 1 ps;


    -- Print the configuration to the log
    -- report_global_ctrl(VOID);
    -- report_msg_id_panel(VOID);

    -- Log control. With everything disabled only alerts (errors) and the final summary show up.
    -- To see every BFM transaction in the transcript, enable just the BFM messages:
    --   enable_log_msg(ID_BFM);       (or enable_log_msg(ALL_MESSAGES) for everything, very verbose)
    --enable_log_msg(ALL_MESSAGES);
    disable_log_msg(ALL_MESSAGES);
    --enable_log_msg(ID_LOG_HDR);

    log(ID_LOG_HDR, "Start Simulation of TB for custom axi lite IP", C_SCOPE);

    -- release active-low resetn signal
    -- Hold reset for 10 clocks, release it, then give the IP another 10 clocks to settle.
    resetn  <= '0';
    wait for c_clkperiod*10;
    resetn  <= '1';
    wait for c_clkperiod*10;

    -- initialize axi lite signals
    -- The record signal has no defined value until it is initialized. This function drives
    -- the master-side wires to their idle values (valid = '0', address and data = 0) and the
    -- slave-side wires to 'Z' so the DUT can drive them.
    -- Do it before the first BFM call. Doing it before the reset is released (at time 0)
    -- would be a safer habit, because the IP then never sees undefined inputs.
    axilite_if <= init_axilite_if_signals(c_axi_addr_width,c_axi_data_width);
    wait for c_clkperiod;

    --==================================================================================================
    -- Test 1: read the switches through reg0
    -- Stimulus: drive the switch pins directly. They are plain inputs, no AXI involved.
    -- Check: reg0 is wired to sw_i, so an AXI read of address 0x0 must return the same value.
    --------------------------------------------------------------------------------------
    -- assign a value to switches
    sw_i    <= x"3C";
    wait for c_clkperiod*10;

    -- read the switch value and check, which is the reg0 of axi lite registers
    v_addr  := c_reg0_addr;
    v_data  :=  x"0000003C";    -- 32-bit register, the upper 24 bits are zero
    axilite_check(v_addr, v_data, "0x3C expected");
    wait for c_clkperiod*10;

    --==================================================================================================
    -- Test 2: write the LED register through reg1
    -- Stimulus: an AXI write to address 0x4.
    -- Check: led_o is the low byte of reg1, so the LED pins must now show the written value.
    -- led_o is checked straight on the pin with check_value, not by reading reg1 back over AXI.
    -- A read-back through axilite_check would only prove that the register stores the value,
    -- not that the pins follow it.
    --------------------------------------------------------------------------------------
    -- write switch value to leds register, which is reg1 of axi lite registers
    v_addr  := c_reg1_addr;
    v_data  :=  x"0000003C";
    axilite_write(v_addr, v_data, "0x3C is written");
    wait for c_clkperiod*10;    -- the register output has already settled after the 10 clocks

    -- check led value, which must be 0x3C
    -- check_value(value, expected, alert level, message): it looks at the signal at this instant.
    check_value(led_o, x"3C", ERROR, "");
    wait for 1 ps;

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
