# Button-Selectable Timer & LED Counter

In the previous project, we built a [Debouncer](vhd03_debouncer/README.md) — now it's time to use it. This project implements a **clock-based timer with selectable periods**, controlled by a single push button, driving a **2-bit LED counter**. Target board is CMOD A7 so peripherals are limited to one button and two LEDs, but the design scales easily.

Source files are in `src/` as usual.

## Core Idea

A free-running timer increments every clock cycle. When it reaches a programmable limit (`timer_lim`), the 2-bit LED counter increments and the timer resets. Pressing the button cycles `timer_lim` through four presets, changing the **blink rate** in real time.

## Clock & Timing

`CLK_FREQ` is a generic (default **12 MHz**). The four timing constants are derived directly from it:

| State        | Constant   | Value             |
|--------------|------------|-------------------|
| `s_LIM2S`    | `LIM2S`    | `CLK_FREQ * 2`    |
| `s_LIM1S`    | `LIM1S`    | `CLK_FREQ`        |
| `s_LIM500mS` | `LIM500mS` | `CLK_FREQ / 2`    |
| `s_LIM250mS` | `LIM250mS` | `CLK_FREQ / 4`    |

This makes the design portable — changing `CLK_FREQ` at instantiation recalculates all limits automatically.

## Counter Logic (`pTIMER`)

`timer` increments every rising edge. When it reaches `timer_lim`:

- `timer` resets to 0
- `counter` increments (2-bit `unsigned`, wraps naturally at 3 → 0)
- `led <= counter` drives the LEDs directly

Note: the check `if counter = 15` in the code is unreachable since `counter` is 2-bit — it wraps at 3 automatically via `unsigned` overflow. That line can be safely removed.

## Button FSM & Edge Detection (`pBTN`)

A simple FSM cycles through the four timing states on each button press:

```
s_LIM2S → s_LIM1S → s_LIM500mS → s_LIM250mS → s_LIM2S → ...
```

Button presses are edge-detected using a `btn0_prev` register:

```vhdl
if btn0_debounced = '1' and btn0_prev = '0' then
    -- rising edge detected → change state
end if;
btn0_prev <= btn0_debounced;
```

`btn0_prev` captures the debounced button value from the previous cycle. The condition fires only on the transition from `'0'` to `'1'` — a clean single-cycle pulse regardless of how long the button is held.

Note the pre-assignment pattern here: `timer_lim` is updated in the current state alongside the state transition — not at the entry of the next state — so it takes effect exactly when the FSM arrives at the new state. This is the same 1-cycle scheduling behavior covered in the [Debouncer](vhd03_debouncer/README.md#pre-assigning-signals-before-a-state-transition).

## Debouncer Instantiation

The debouncer from the previous project is instantiated directly:

```vhdl
inst_DEB: entity work.debouncer 
generic map(
    CLK_FREQ   => 12_000_000,
    DEBTIME_MS => 5,               
    ACTIVE_LOW => true       
)
port map(
    clk     => clk,
    sig_in  => btn0,
    sig_out => btn0_debounced
);
```

`btn0` passes through the debouncer before reaching the FSM — this is the right place to handle metastability and contact bounce.

---
⬅️  [MAIN PAGE](../README.md)