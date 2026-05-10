
# Building Your Own $500 Glitch Tool – Reference Design

This document provides a complete, **reproducible guide** to building a voltage glitch injector capable of corrupting AI inference on an unprotected GPU (RTX 4090 / 3090). The same tool is used in our live demonstrations.

**Total BOM cost (excluding oscilloscope): ~$310**  
**With optional oscilloscope: ~$900** (still far below the $500 headline figure for repeatable attacks)

---

## 1. Bill of Materials (BOM)

| Component                      | Model / Specification                     | Quantity | Approx. Cost (USD) |
|--------------------------------|-------------------------------------------|----------|--------------------|
| FPGA board                     | Arty A7‑100T (Artix‑7)                    | 1        | $269               |
| MOSFET switch                  | IPP075N15N5 (or any logic‑level N‑channel with low Rds(on)) | 1        | $3.50              |
| Capacitors (ceramic)           | 100 nF, 1 µF, 10 µF                       | 1 each   | $2.00              |
| Resistor                       | 10 Ω, 1/4 W                               | 1        | $0.10              |
| Connector                      | Female pin header (for PMOD)              | 1        | $1.00              |
| Power supply for Arty A7       | 12V DC, 2A (included with most boards)    | 1        | (included)         |
| Oscilloscope (optional but recommended) | Rigol DHO804 (200 MHz, 4‑channel) | 1        | $599               |
| Wires, breadboard / prototype PCB | Generic                                    | as needed | $10                |
| **Total (excluding scope)**    |                                           |          | **~$285**          |
| **Total (including scope)**    |                                           |          | **~$884**          |

**Note:** If you already own an oscilloscope (any 200 MHz+ model), the out‑of‑pocket cost is ~$285.

---

## 2. Theory of Operation

A voltage glitch is a **short, precise drop** in the power supply rail of a target chip (GPU, CPU, or microcontroller). When timed to a critical instruction (e.g., a comparison or a branch), the chip enters a faulty state – skipping a security check, corrupting a result, or leaking secret data.

Our design injects the glitch by:
1. **Monitoring** a trigger signal from the FPGA (or a software script).
2. **Opening a MOSFET** that briefly shorts the power rail through a low‑resistance path.
3. **Shaping the pulse** with a capacitor to achieve 40–100 ns duration.

The entire circuit is powered from the same 12V supply as the Arty A7, but glitch is applied to the **target’s** power rail (e.g., 1.8V or 0.9V on an RTX 4090).

---

## 3. Circuit Diagram

```text
                     +12V (from Arty A7)
                       |
                      |/
                 Q1   |  (MOSFET IPP075N15N5)
                 +----+----+
                 |    |    |
                 |    +----+--- to target power rail (1.8V / 0.9V)
                 |         |
                 |       +-+-+
                 |       | R1| 10Ω
                 |       +-+-+
                 |         |
                 |         +---- GND (target ground)
                 |
                 +----+----+--- GND (Arty ground)
                      |
                     ===  C1  1 µF
                      |
                     GND
```

**MOSFET pinout (view from top):**
- **Drain** → to target power rail (via 10Ω resistor).
- **Source** → to target ground (common with Arty ground).
- **Gate** → to Arty PMOD pin (e.g., JD0) via a 100Ω resistor (not shown, for current limiting).

**Capacitor placement:** The 1 µF capacitor is soldered directly between drain and source of the MOSFET – it determines the glitch duration.

---

## 4. Assembly Steps

### 4.1. On the Arty A7
1. Connect a **PMOD header** (e.g., JD) to the FPGA.
2. Assign pin **JD0** as output in your bitstream (already done in our pre‑built `.bit`).
3. **No additional firmware change** – our Sentinel IP Core already drives this pin when an attack is emulated.

### 4.2. Glitch Board (breadboard or small PCB)
1. Place the MOSFET on the board.
2. Solder the 1 µF capacitor between **Drain** and **Source** (leads as short as possible).
3. Solder the 10 Ω resistor between **Drain** and the **target power wire** (this limits current and protects the target).
4. Connect **Gate** to a 2‑pin header that will go to PMOD JD0.
5. Connect **Source** to a wire that leads to **target ground**.
6. (Optional) Add a 100 nF capacitor across the 12V input for stability.

### 4.3. Connecting to Target (RTX 4090 / 3090)
**WARNING:** This involves working with a live GPU. Only proceed if you have experience with low‑voltage electronics. We are not responsible for any damage.

1. Identify a **1.8V or 0.9V power rail** on the GPU. On an RTX 4090, you can use the **PCIe edge connector** or a **power phase inductor** (requires soldering skills). For a non‑destructive test, use a PCIe extension cable and tap the 1.8V pin.
2. Solder the **Drain wire** (from the 10Ω resistor) to that rail.
3. Solder the **Source wire** to a nearby ground plane.
4. Connect the **Gate header** to PMOD JD0 (Arty A7).

---

## 5. Software Trigger – from Python

Once the hardware is ready, use our `heatmap_glitch.py` script to trigger the glitch at the exact moment of a neural network inference.

```bash
cd fpga_shield/poc
python3 heatmap_glitch.py --gpu 0 --model mobilenet_v2 \
    --image samples/falcon.jpg \
    --trigger-port /dev/ttyACM0 \
    --confidence-threshold 0.5
```

The script will:
- Load the model and an image.
- Send a trigger pulse (via USB‑UART to the Arty) 10 µs before the critical convolution.
- The Arty then drives JD0 high for **45 ns** (programmed in the Sentinel FSM).
- The MOSFET opens, pulling down the target power rail for the same duration.

**Result without TOTAL Shield:** Incorrect classification (Falcon → Camel).  
**Result with TOTAL Shield active:** Attack detected <310 ns after glitch starts; NMI asserted; model output unchanged.

---

## 6. Tuning the Glitch

| Parameter          | How to Adjust                                | Typical Range       |
|--------------------|----------------------------------------------|---------------------|
| **Glitch duration**| Change capacitor value (C1)                  | 20–100 ns           |
| **Glitch depth**   | Add series resistor between drain and target | 0–50 Ω              |
| **Trigger delay**  | Modify `glitch_delay_cycles` in Verilog      | 0–1000 cycles       |

For best results, **start with a 45 ns glitch** (our proven value). Use an oscilloscope to capture the actual waveform at the target power rail.

---

## 7. Safety Notes

- **Always connect grounds** (Arty ground and target ground) before applying power.
- **Start with a low‑cost GPU** (e.g., a used GTX 1060) for initial tests.
- **Do not exceed 2V** on the glitch output – many modern GPU rails are 0.9V.
- **The glitch tool is for research and demonstration only.** Do not use on production systems without authorization.

---

## 8. Troubleshooting

| Symptom                          | Likely cause                          | Fix                                 |
|----------------------------------|---------------------------------------|-------------------------------------|
| No glitch observed on oscilloscope | MOSFET not switching                 | Check gate voltage (should be 3.3V from Arty) |
| GPU crashes or resets            | Glitch too deep or too long           | Increase series resistor, reduce C1 |
| Model still misclassifies with Shield | Shield not enabled in bitstream  | Use our pre‑built bitstream or enable `ENABLE_SHIELD` parameter |
| UART no output                   | Wrong baud rate (115200) or wrong port| Use `ls /dev/ttyUSB*` and set correct port |

---

## 9. References

- [Voltage Glitching Tutorial (Riscure)](https://www.riscure.com/blog/voltage-glitching)
- [TOTAL Shield PoC Video](#) (available upon request)
- [Arty A7 Reference Manual](https://digilent.com/reference/programmable-logic/arty-a7/start)

---

## 10. Request Pre‑Built Glitch Tool

If you prefer not to build the tool yourself, qualified partners (government, critical infrastructure, hyperscalers) can request a **fully assembled glitch tool** (Arty A7 + MOSFET board + cables) pre‑programmed with TOTAL Shield.

📧 **Send request to:** `totalprotocol@proton.me`  
Subject: *“Glitch Tool Request – [Your Organization]”*

Price: **$500 + shipping** (includes one Arty A7, pre‑programmed bitstream, and glitch board).

---

*“The best way to prove security is to let anyone try to break it – and fail.”*
```

