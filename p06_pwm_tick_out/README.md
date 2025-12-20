# PWM Output Module (Generic Clock & Frequency)

This module implements a **clock-synchronous PWM generator** with a fixed PWM frequency and a programmable duty cycle.  
The design is **fully generic** with respect to system clock frequency and duty resolution.

Example configuration:
- 40 MHz clock → 200 kHz PWM → 200 duty steps

## Key Generics
- `CLK_FREQ` : System clock frequency (Hz)
- `PWM_FREQ` : Desired PWM frequency (Hz)
- `N`        : Duty-cycle input width (bits)

Derived parameter:
- `PWM_PERIOD = CLK_FREQ / PWM_FREQ` (integer clock cycles)

## Core Mechanism
- A counter (`timer`) runs from **0 to PWM_PERIOD − 1**
- A clamped duty value (`duty_int`) defines how many ticks the output stays HIGH
- PWM rule:
  - `pwm_out = '1'` while `timer < duty_int`
  - `pwm_out = '0'` otherwise

This guarantees correct duty behavior, including 0% and 100%.

## Duty Cycle Handling
- Input: `duty_cycle` (`N` bits)
- Valid range: `0 … PWM_PERIOD`
- Values above `PWM_PERIOD` are clamped

Meaning:
- `0`              → always LOW
- `PWM_PERIOD / 2` → ~50% duty
- `PWM_PERIOD`     → always HIGH

## Duty Width Selection (`N`)
The duty input width must be large enough to represent `PWM_PERIOD`.

Rule:
`N ≥ ceil(log2(PWM_PERIOD + 1))`


Examples:
| CLK_FREQ | PWM_FREQ | PWM_PERIOD | Required N |
|---------|----------|------------|------------|
| 12 MHz  | 200 kHz  | 60         | 6 bits     |
| 40 MHz  | 200 kHz  | 200        | 8 bits     |
| 100 MHz | 200 kHz  | 500        | 9 bits     |

I connected a VIO and gave duty cycles and visualize the pwm out put with Analog Discovery 3 like the following.

![alt text](image.png)

---
⬅️  [MAIN PAGE](../README.md)