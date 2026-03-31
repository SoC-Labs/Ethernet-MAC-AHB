# HA1588 APB Verification Plan

Verification plan for the `ha1588_apb` IEEE 1588 PTP timestamping unit with
APB slave interface, targeting ASIC tapeout with code coverage closure
and X-propagation analysis.

## Design Overview

```
APB Slave -> apb_to_wb -> wb_slv_wrapper -> ha1588
                                              |
                          +---+---+---+-------+
                          |   |   |   |
                         rgs rtc tsu  tsu
                                 (rx) (tx)
```

- **Register space**: 128 bytes (0x00-0x7C), 32 registers
- **Clock domains**: pclk (100 MHz), rtc_clk (125 MHz), rx_gmii_clk, tx_gmii_clk
- **CDC crossings**: reg->rtc (time_ld, period_ld, adj_ld, time_rd), gmii->rtc (timestamp capture), reg->gmii (queue read/reset)

---

## Cocotb Test Plan

### Layer 1: APB Bridge Protocol (11 tests)

These tests verify the apb_to_wb bridge operates correctly when integrated
with the ha1588 register file. They exercise the APB protocol through the
full bridge stack.

| ID | Test | Description |
|----|------|-------------|
| 1.1 | `test_scratch_register` | Basic APB write/read to scratch register |
| 1.2 | `test_reg_write_readback` | Write known patterns to all 10 RW registers and read back |
| 1.3 | `test_rtc_ctrl_register` | Write RTC_CTRL bits, verify readback (bits [4:2] writable) |
| 1.4 | `test_tsu_ctrl_registers` | Write TSU RX/TX control (reset, read_queue) |
| 1.5 | `test_tsu_msgid_mask` | Write PTP message ID mask via TSU_RXSTAT/TXSTAT [31:24] |
| 1.6 | `test_walking_ones` | Walking-1 pattern on scratch register (stuck-at detection) |
| 1.7 | `test_walking_zeros` | Walking-0 pattern on scratch register |
| 1.8 | `test_back_to_back_reg_access` | Rapid consecutive APB transfers (write-write, write-read, read-read) |
| 1.9 | `test_full_address_space` | Read every register address 0x00-0x7C (all 32 words) |
| 1.10 | `test_byte_strobe_variations` | APB PSTRB: full-word, half-word, byte (verify WB SEL forwarding) |
| 1.11 | `test_apb_idle_no_wb_activity` | PSEL=0 generates no WB cycle; bus stays clean |

### Layer 2: RTC Functional (8 tests)

These tests verify the Real-Time Clock core through the APB register
interface, exercising all RTC control operations and CDC crossings.

| ID | Test | Description |
|----|------|-------------|
| 2.1 | `test_rtc_period_load` | Write PERIOD_H/L, assert SET_PERIOD, verify time advances |
| 2.2 | `test_rtc_time_load` | Write TIME_SEC/NSC, assert SET_TIME, GET_TIME readback |
| 2.3 | `test_rtc_ptp_output` | Load period, let RTC tick, verify rtc_time_ptp_ns/sec non-zero |
| 2.4 | `test_rtc_second_rollover` | Set ns near 999,999,999, let rollover, verify sec increments |
| 2.5 | `test_rtc_one_pps` | Set 8ns period (125 MHz), wait for rtc_time_one_pps pulse |
| 2.6 | `test_rtc_frequency_adjustment` | Write ADJ_PERIOD, ADJ_NUM, SET_ADJ, poll adj_ld_done |
| 2.7 | `test_rtc_soft_reset` | Assert SET_RESET (RTC_CTRL[4]), verify time clears to zero |
| 2.8 | `test_rtc_get_time_handshake` | Exercise GET_TIME -> poll time_ok CDC handshake multiple times |

### Layer 3: TSU PTP Timestamping (10 tests)

These tests inject GMII frames and verify that the TSU captures timestamps
and makes them available via the register interface.

| ID | Test | Description |
|----|------|-------------|
| 3.1 | `test_tsu_rx_l2_ptp_sync` | Inject L2 PTP Sync frame (EtherType 0x88F7) on RX GMII, read timestamp |
| 3.2 | `test_tsu_rx_l4_ipv4_ptp` | Inject PTP over IPv4/UDP (port 319/320), verify timestamp capture |
| 3.3 | `test_tsu_rx_l4_ipv6_ptp` | Inject PTP over IPv6/UDP, verify timestamp capture |
| 3.4 | `test_tsu_rx_vlan_ptp` | Inject PTP with single and double VLAN tags |
| 3.5 | `test_tsu_rx_msgid_filtering` | Set message ID mask, inject multiple types, verify only masked pass |
| 3.6 | `test_tsu_rx_queue_fill_drain` | Fill queue with multiple PTP frames, drain via register reads |
| 3.7 | `test_tsu_rx_queue_reset` | Fill queue, assert TSU_RXCTRL[1], verify queue empties |
| 3.8 | `test_tsu_rx_giga_vs_mii` | Test rx_giga_mode=1 (8-bit) and rx_giga_mode=0 (4-bit nibble) |
| 3.9 | `test_tsu_tx_l2_ptp_sync` | Inject L2 PTP on TX GMII path, read TX queue timestamp |
| 3.10 | `test_tsu_tx_queue_reset` | Fill TX queue, reset, verify empty |

### Layer 4: Reset and Edge Cases (6 tests)

| ID | Test | Description |
|----|------|-------------|
| 4.1 | `test_hard_reset_clears_state` | Assert presetn, verify all registers return to defaults |
| 4.2 | `test_reset_during_transfer` | Assert reset mid-APB transfer, verify clean recovery |
| 4.3 | `test_queue_overflow` | Fill TSU queue beyond 16 entries, verify no corruption |
| 4.4 | `test_queue_underflow` | Read from empty TSU queue, verify no hang or error |
| 4.5 | `test_concurrent_rx_tx_timestamps` | Inject PTP on both RX and TX simultaneously |
| 4.6 | `test_cdc_time_read_under_load` | Rapid GET_TIME requests while RTC is actively ticking |

### Layer 5: Stress and Random (3 tests)

| ID | Test | Description |
|----|------|-------------|
| 5.1 | `test_random_register_traffic` | 500 random register reads/writes across full address space |
| 5.2 | `test_rtc_extended_run` | Let RTC run for simulated 10ms, verify time accuracy within tolerance |
| 5.3 | `test_mixed_functional` | Combined: load time, set period, inject PTP frames, read timestamps |

**Total Cocotb tests: 38**

---

## UVM Test Plan

The UVM testbench uses Synopsys VC VIP for APB master stimulus generation
and a custom register model for scoreboard checking.

### UVM Test Classes

| Test | Sequences Used | Description | Transactions |
|------|---------------|-------------|--------------|
| `ha1588_apb_single_test` | apb_single_write, apb_single_read | Single RW to each register | ~20 |
| `ha1588_apb_write_read_test` | apb_write_read_sequence | Write-then-readback for all RW registers | ~20 |
| `ha1588_apb_back_to_back_test` | apb_back_to_back_sequence | Rapid consecutive transfers, no idle | ~50 |
| `ha1588_apb_gapping_test` | apb_gapping_sequence | Randomized idle gaps between transfers | 200 |
| `ha1588_apb_random_test` | apb_mixed_sequence | Constrained-random addresses, data, direction | 1000 |
| `ha1588_apb_error_test` | apb_error_sequence | Drive unsupported address ranges, check PSLVERR | ~10 |
| `ha1588_apb_rtc_functional_test` | apb_rtc_sequence | RTC period load, time set, GET_TIME handshake | ~50 |

### UVM Sequences

| Sequence | Description |
|----------|-------------|
| `apb_single_write_sequence` | Single APB write to parameterised address |
| `apb_single_read_sequence` | Single APB read from parameterised address |
| `apb_write_read_sequence` | Write then immediate readback |
| `apb_back_to_back_sequence` | Multiple transfers with no idle gaps |
| `apb_gapping_sequence` | Transfers with randomised idle gaps (0-10 cycles) |
| `apb_mixed_sequence` | Constrained-random: address, data, direction |
| `apb_rtc_sequence` | RTC period/time load with register polling |
| `apb_error_sequence` | Out-of-range address, verify PSLVERR |

### UVM Scoreboard

- **Register shadow model**: Maintains expected values for all RW registers
- **Write check**: Updates shadow on APB write
- **Read check**: Compares APB read data against shadow for RW registers
- **Status registers**: Read-only, not shadow-checked (contents depend on HW state)
- **Mismatch counting**: Reports pass/fail in UVM report_phase

### UVM Coverage

| Covergroup | Bins |
|-----------|------|
| `apb_addr_cg` | All 32 register addresses x {read, write} |
| `apb_data_pattern_cg` | {all_zeros, all_ones, walking_1, walking_0, alternating, random} |
| `apb_transfer_type_cg` | {write-write, write-read, read-write, read-read} consecutive |
| `apb_strobe_cg` | {0xF, 0x3, 0xC, 0x1, 0x8, 0x5, 0xA} |
| `rtc_ctrl_cg` | Each RTC_CTRL bit [4:0] exercised individually |
| `tsu_ctrl_cg` | TSU_RXCTRL and TSU_TXCTRL bits exercised |

**Total UVM tests: 7**

---

## Formal Verification (X-propagation)

### ha1588_apb xprop

VC Formal X-propagation analysis verifies no X-state propagates to any
output after a valid reset sequence through normal APB operation.

**Assumptions:**
- APB inputs well-formed: PSEL, PENABLE, PWRITE not X
- GMII inputs well-formed: rx/tx_gmii_ctrl, rx/tx_gmii_data not X
- RTC clock toggling

**Checks:**
- `check_xprop -type {hold reset_value}` on all outputs
- All APB outputs (PRDATA, PREADY, PSLVERR) X-free
- All RTC outputs (rtc_time_ptp_ns/sec, rtc_time_one_pps) X-free

### apb_to_wb xprop (bridge repo)

Already set up in `amba_wb_bridges/formal/apb_to_wb/xprop.tcl`.

---

## Code Coverage Targets (ASIC)

| Metric | Target | Notes |
|--------|--------|-------|
| Line coverage | >= 95% | Excluding unreachable dead code |
| Branch coverage | >= 90% | All if/else/case arms |
| Condition coverage | >= 85% | Boolean sub-expressions |
| Toggle coverage | >= 90% | All flip-flop outputs |
| FSM coverage | 100% | All states and transitions |

Coverage is collected via VCS `-cm line+cond+tgl+fsm+branch` flags and merged
across all test runs using `urg`.
