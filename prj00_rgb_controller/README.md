# RGB LED Controller

An RGB LED controller for the **CMOD A7** onboard RGB LED. Wraps three instances of the [Tick-Based PWM module](../vhd05_pwm_tick_out/README.md) into a single component and drives them from a combinational color lookup that cycles through 9 preset colors.

---

## Source Files

| File | Description |
|------|-------------|
| `src/pwm_rgb_led.vhd` | RGB controller — maps 3× 8-bit color values to 3 PWM channels |
| `src/rgb_top.vhd` | Top level — cycles through 9 preset colors, one per second |

---

## RGB Controller (`pwm_rgb_led.vhd`)

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

| Index | Color     | R    | G    | B    |
|-------|-----------|------|------|------|
| 0     | Red       | `FF` | `00` | `00` |
| 1     | Green     | `00` | `FF` | `00` |
| 2     | Blue      | `00` | `00` | `FF` |
| 3     | White     | `FF` | `FF` | `FF` |
| 4     | Yellow    | `FF` | `FF` | `00` |
| 5     | Cyan      | `00` | `FF` | `FF` |
| 6     | Magenta   | `FF` | `00` | `FF` |
| 7     | Orange    | `FF` | `60` | `00` |
| 8     | Dim White | `40` | `40` | `40` |

The lookup is implemented as a **combinational process** — `color_count` changes → R/G/B update immediately in the same delta cycle, no clock edge needed. The PWM controller latches the new duty value at the next period boundary regardless.

---
⬅️ [MAIN PAGE](../README.md) | [Tick-Based PWM Module](../vhd05_pwm_tick_out/README.md)