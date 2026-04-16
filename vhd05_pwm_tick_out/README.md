# Tick-Based PWM Output Module

This module implements a **clock-synchronous PWM generator** with a fixed PWM frequency and a programmable duty cycle. The design is fully generic with respect to system clock frequency, PWM frequency, and duty resolution.

---

## Source Files

| File | Description |
|------|-------------|
| `src/pwm_tick_based.vhd` | Core PWM generator — parametric frequency and duty resolution |
| `src/rgb_controller.vhd` | RGB controller — maps 3× 8-bit color values to 3 PWM channels |
| `src/rgb_top.vhd` | Top level — cycles through 9 preset colors, one per second |

---

## Core Mechanism

A free-running `timer` counts from `0` to `PWM_PERIOD − 1`. The output is compared against a latched duty value each clock cycle:

```
pwm_out = '1'  while  timer < duty_latched
pwm_out = '0'  otherwise
```

This naturally handles the 0% and 100% edge cases:

- `duty_latched = 0`          → output always LOW
- `duty_latched = PWM_PERIOD` → output always HIGH

## Generics

```vhdl
generic(
    CLK_FREQ : integer := 40_000_000; -- Hz
    PWM_FREQ : integer := 200_000;    -- Hz
    N        : integer := 8           -- duty cycle input width in bits
);
```

`PWM_PERIOD` is derived internally:

```
PWM_PERIOD = CLK_FREQ / PWM_FREQ
```

For 40 MHz and 200 kHz: `PWM_PERIOD = 200` — meaning 200 discrete duty steps.

## Choosing N Correctly

`N` controls the width of the `duty_cycle` input. It must be large enough to represent `PWM_PERIOD`:

```
N ≥ ceil(log2(PWM_PERIOD + 1))
```

If `N` is too small, the input can never reach `PWM_PERIOD` and 100% duty cycle becomes unreachable. Values above `PWM_PERIOD` are clamped safely regardless.

| CLK_FREQ | PWM_FREQ | PWM_PERIOD | Minimum N |
|----------|----------|------------|-----------|
| 12 MHz   | 200 kHz  | 60         | 6 bits    |
| 40 MHz   | 200 kHz  | 200        | 8 bits    |
| 100 MHz  | 200 kHz  | 500        | 9 bits    |

## Duty Cycle Handling — Three Stages

The duty cycle goes through three stages from input to output:

**1. Clamp (`duty_int`) — combinational**

```vhdl
duty_int <= PWM_PERIOD when (to_integer(unsigned(duty_cycle)) > PWM_PERIOD)
                       else to_integer(unsigned(duty_cycle));
```

`duty_int` updates immediately whenever `duty_cycle` changes. Values above `PWM_PERIOD` are saturated to `PWM_PERIOD`.

**2. Latch (`duty_latched`) — registered at period boundary**

```vhdl
if timer = 0 then
    duty_latched <= duty_int;
end if;
```

`duty_latched` only captures `duty_int` at the start of each PWM period (`timer = 0`). This ensures that a duty change mid-period does not cause an irregular pulse — the new value always takes effect on the next clean period boundary.

**3. Compare (`pwm_out`) — registered**

```vhdl
if timer < duty_latched then
    pwm_out <= '1';
else
    pwm_out <= '0';
end if;
```

Since both `duty_latched` and `pwm_out` are updated in the same registered process, there is no timing mismatch between them.

## Simulation Result

![simulation](docs/tb.png)

## Hardware Validation

I connected a VIO to drive `duty_cycle` and verified the output with an **Analog Discovery 3**. The waveform below shows the PWM output at a set duty cycle — frequency and high time matched the expected values.

![pwm_scope](docs/ad3.png)

---

## RGB Controller (`rgb_controller.vhd`)

Wraps three `pwm_tick_based` instances into a single RGB LED controller. Takes three 8-bit color values and maps them to independent PWM duty cycles.

**Duty mapping:**

```
duty = R_i8 * (PWM_PERIOD / 2) / 255
```

The output is capped at **50% duty cycle** as required by Digilent for the CMOD A7 onboard RGB LED. `PWM_PERIOD / 2` is a compile-time constant so the multiplication resolves to a single DSP48 slice per channel.

**Active-low output:** the CMOD A7 RGB LED is active-low — `'0'` turns a channel on. The controller inverts all three PWM outputs before driving the pins:

```vhdl
led0_r <= not pwm_red;
led0_g <= not pwm_green;
led0_b <= not pwm_blue;
```

PWM settings for CMOD A7:

```vhdl
CLK_FREQ => 12_000_000,
PWM_FREQ => 1_000,   -- 1 kHz, well above flicker threshold
N        => 14       -- ceil(log2(12001)) = 14 bits for PWM_PERIOD = 12_000
```

---

## Color Cycling Top Level (`rgb_top.vhd`)

Cycles through 9 preset colors, holding each for one second. Uses a free-running 1-second timer to increment `color_count`, which drives a combinational color lookup:

| Index | Color | R | G | B |
|-------|-------|---|---|---|
| 0 | Red | `FF` | `00` | `00` |
| 1 | Green | `00` | `FF` | `00` |
| 2 | Blue | `00` | `00` | `FF` |
| 3 | White | `FF` | `FF` | `FF` |
| 4 | Yellow | `FF` | `FF` | `00` |
| 5 | Cyan | `00` | `FF` | `FF` |
| 6 | Magenta | `FF` | `00` | `FF` |
| 7 | Orange | `FF` | `60` | `00` |
| 8 | Dim White | `40` | `40` | `40` |

The lookup is implemented as a **combinational process** — `color_count` changes → R/G/B update immediately in the same delta cycle, no clock edge needed. The PWM controller latches the new duty value at the next period boundary regardless.

---
⬅️ [MAIN PAGE](../README.md) | ➡️ [PWM Percentage Output](../vhd06_pwm_percent/README.md)