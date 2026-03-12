# Button-Selectable Timer & LED Counter

This module implements a **clock-based timer with selectable periods**, controlled by two push buttons, and drives a **2-bit LED counter**.

## Core Idea
A free-running counter increments whenever a timer reaches a programmable limit.  
The timer limit is changed at runtime using buttons, effectively changing the **blink / count rate**.

## Clock & Timing
- `CLK_FREQ` is a generic (default **12 MHz**)
- Timing constants are derived directly from it:
  - **250 ms** → `CLK_FREQ / 4`
  - **500 ms** → `CLK_FREQ / 2`
  - **1 s** → `CLK_FREQ`
  - **2 s** → `CLK_FREQ * 2`

This makes the design **portable across different clock frequencies**.

## Counter Logic (`p_COUNTER`)
- `timer` increments on every rising clock edge
- When `timer == timer_lim`:
  - `counter` increments (2-bit, natural wrap-around)
  - `timer` resets to 0
- `led <= counter`, LEDs directly display the counter value

## Timer Selection FSM (`p_LIM_CHOICE`)
- Uses a **finite state machine** (`lim_state`) to track the active timing mode:
  - `s_250mS`, `s_500mS`, `s_1S`, `s_2S`
- Button presses are detected using **edge detection** via `btn_prev`

### Button Functions
- `btn(0)` → increase period (slower counting)
  - 250 ms → 500 ms → 1 s → 2 s
- `btn(1)` → decrease period (faster counting)
  - 2 s → 1 s → 500 ms → 250 ms

No wrap-around beyond the min/max limits (states are clamped).

## Design Notes
- Clear separation of concerns:
  - One process for timing & counting
  - One process for button handling & FSM
- Edge detection prevents repeated triggers while holding a button
- Integer-based timers are simple and readable, assuming synthesis supports the range

## Use Cases
- Learning **clock-derived timing**
- Basic **button edge detection**
- FSM-controlled runtime parameter changes
- Human-visible timing effects on FPGA (LED blink rates)

---
⬅️  [MAIN PAGE](../README.md)
