# HA1588 AHB Verification Plan

Verification plan for the `ha1588_ahb` IEEE 1588 PTP timestamping unit with
AHB-Lite slave interface, targeting ASIC tapeout with code coverage closure
and X-propagation analysis.

## Design Overview

```
AHB Slave -> ahb3lite_to_wb -> wb_slv_wrapper -> ha1588
                                                   |
                               +---+---+---+-------+
                               |   |   |   |
                              rgs rtc tsu  tsu
                                      (rx) (tx)
```

- **Register space**: 128 bytes (0x00-0x7C), 32 registers
- **Clock domains**: hclk (100 MHz), rtc_clk (125 MHz), rx_gmii_clk, tx_gmii_clk
- **CDC crossings**: reg->rtc (time_ld, period_ld, adj_ld, time_rd), gmii->rtc (timestamp capture), reg->gmii (queue read/reset)

---

## Functional Coverage Points

### FC1: Register Access Coverage

| ID | Coverage Point | Description | Bins |
|----|---------------|-------------|------|
| FC1.1 | `reg_addr_hit` | Every register address accessed (R and W) | 32 addresses x {read, write} |
| FC1.2 | `reg_data_pattern` | Data patterns exercised on RW registers | {all_zeros, all_ones, walking_1, walking_0, alternating} |
| FC1.3 | `reg_back_to_back` | Consecutive accesses without idle cycles | {write-write, write-read, read-write, read-read} |
| FC1.4 | `reg_ctrl_bits` | Each RTC_CTRL bit exercised individually | bits [4:0]: {SET_RESET, SET_TIME, SET_PERIOD, SET_ADJ, GET_TIME} |

### FC2: RTC (Real-Time Clock) Coverage

| ID | Coverage Point | Description | Bins |
|----|---------------|-------------|------|
| FC2.1 | `rtc_period_load` | Period register loaded and takes effect | {8ns/0frac, custom_int, custom_frac, zero} |
| FC2.2 | `rtc_time_load` | Direct time set via SET_TIME | {zero, mid_range, near_rollover, max_ns} |
| FC2.3 | `rtc_time_read` | GET_TIME handshake completes (time_ok asserted) | hit/miss |
| FC2.4 | `rtc_second_rollover` | Nanosecond counter wraps at 1,000,000,000 ns | observed |
| FC2.5 | `rtc_one_pps` | One-PPS output pulses | observed, count >= 1 |
| FC2.6 | `rtc_adj_load` | Frequency adjustment loaded and adj_ld_done | {small_adj, large_adj, countdown_complete} |
| FC2.7 | `rtc_ptp_output` | PTP ns/sec output pins driven non-zero | {ns > 0, sec > 0} |
| FC2.8 | `rtc_reset` | RTC soft reset via SET_RESET clears state | observed |

### FC3: TSU (Timestamp Unit) Coverage -- RX Path

| ID | Coverage Point | Description | Bins |
|----|---------------|-------------|------|
| FC3.1 | `tsu_rx_ptp_l2` | L2 PTP frame (EtherType 0x88f7) detected on RX | observed |
| FC3.2 | `tsu_rx_ptp_l4_ipv4` | L4 PTP over IPv4/UDP detected on RX | observed |
| FC3.3 | `tsu_rx_ptp_l4_ipv6` | L4 PTP over IPv6/UDP detected on RX | observed |
| FC3.4 | `tsu_rx_vlan` | PTP frame with VLAN tag parsed correctly | {single_vlan, double_vlan} |
| FC3.5 | `tsu_rx_msgid_mask` | Message ID mask filters correct PTP types | {sync_only, all_event, custom_mask} |
| FC3.6 | `tsu_rx_queue_write` | Timestamp enqueued in RX FIFO | observed |
| FC3.7 | `tsu_rx_queue_read` | Timestamp dequeued via register interface | {single_entry, multiple_entries} |
| FC3.8 | `tsu_rx_queue_status` | Queue fill level read from status register | {empty, partial, near_full} |
| FC3.9 | `tsu_rx_queue_reset` | Queue reset clears entries | observed |
| FC3.10 | `tsu_rx_giga_mode` | Gigabit mode (8-bit GMII) vs Fast Ethernet (4-bit MII nibble) | {giga=1, giga=0} |
| FC3.11 | `tsu_rx_timestamp_accuracy` | Captured timestamp within tolerance of expected | abs_error < 100ns |

### FC4: TSU (Timestamp Unit) Coverage -- TX Path

| ID | Coverage Point | Description | Bins |
|----|---------------|-------------|------|
| FC4.1 | `tsu_tx_ptp_l2` | L2 PTP frame detected on TX | observed |
| FC4.2 | `tsu_tx_ptp_l4_ipv4` | L4 PTP over IPv4/UDP detected on TX | observed |
| FC4.3 | `tsu_tx_queue_write` | Timestamp enqueued in TX FIFO | observed |
| FC4.4 | `tsu_tx_queue_read` | Timestamp dequeued via register interface | observed |
| FC4.5 | `tsu_tx_queue_reset` | Queue reset clears entries | observed |
| FC4.6 | `tsu_tx_giga_mode` | Gigabit vs Fast Ethernet modes | {giga=1, giga=0} |

### FC5: Clock Domain Crossing (CDC)

| ID | Coverage Point | Description | Bins |
|----|---------------|-------------|------|
| FC5.1 | `cdc_time_rd_handshake` | hclk->rtc_clk GET_TIME request/ack completes | observed |
| FC5.2 | `cdc_period_ld` | hclk->rtc_clk period load pulse crosses | observed |
| FC5.3 | `cdc_time_ld` | hclk->rtc_clk time load pulse crosses | observed |
| FC5.4 | `cdc_adj_ld` | hclk->rtc_clk adjustment load pulse crosses | observed |
| FC5.5 | `cdc_tsu_timestamp` | gmii_clk->rtc_clk timestamp capture CDC | observed |
| FC5.6 | `cdc_queue_async` | GMII write clock -> hclk read clock (async FIFO) | observed |

### FC6: Reset and Error Coverage

| ID | Coverage Point | Description | Bins |
|----|---------------|-------------|------|
| FC6.1 | `hard_reset` | Global hresetn assertion clears all state | observed |
| FC6.2 | `rtc_soft_reset` | RTC_CTRL[4] SET_RESET | observed |
| FC6.3 | `tsu_rx_soft_reset` | TSU_RXCTRL[1] queue reset | observed |
| FC6.4 | `tsu_tx_soft_reset` | TSU_TXCTRL[1] queue reset | observed |
| FC6.5 | `queue_overflow` | Write to full FIFO (overflow protection) | observed |
| FC6.6 | `queue_underflow` | Read from empty FIFO (underflow protection) | observed |

---

## Test Plan

### Layer 1: Register Access (existing tests + coverage enhancement)

| Test | Coverage Points | Status |
|------|----------------|--------|
| `test_scratch_register` | FC1.1, FC1.2 | Existing |
| `test_reg_write_readback` | FC1.1, FC1.2 | Existing |
| `test_rtc_ctrl_register` | FC1.1, FC1.4 | Existing |
| `test_tsu_ctrl_registers` | FC1.1, FC1.4 | Existing |
| `test_tsu_msgid_mask` | FC1.1, FC3.5 | Existing |
| `test_walking_ones` | FC1.2 | Existing |
| `test_walking_zeros` | FC1.2 | Existing |
| `test_back_to_back_reg_access` | FC1.3 | Existing |
| `test_full_address_space` | FC1.1 | Existing |

### Layer 2: RTC Functional (existing + new)

| Test | Coverage Points | Status |
|------|----------------|--------|
| `test_rtc_period_load` | FC2.1, FC2.3 | Existing |
| `test_rtc_time_load` | FC2.2, FC2.3 | Existing |
| `test_rtc_ptp_output` | FC2.7 | Existing |
| `test_rtc_second_rollover` | FC2.4, FC2.5 | **New** |
| `test_rtc_frequency_adjustment` | FC2.6 | **New** |
| `test_rtc_soft_reset` | FC2.8, FC6.2 | **New** |

### Layer 3: TSU PTP Timestamping (new)

| Test | Coverage Points | Status |
|------|----------------|--------|
| `test_tsu_rx_l2_ptp_sync` | FC3.1, FC3.6, FC3.7, FC3.11 | **New** |
| `test_tsu_rx_l4_ipv4_ptp` | FC3.2, FC3.6, FC3.7 | **New** |
| `test_tsu_rx_vlan_ptp` | FC3.4 | **New** |
| `test_tsu_rx_msgid_filtering` | FC3.5 | **New** |
| `test_tsu_rx_giga_vs_mii` | FC3.10 | **New** |
| `test_tsu_rx_queue_fill_drain` | FC3.7, FC3.8 | **New** |
| `test_tsu_rx_queue_reset` | FC3.9, FC6.3 | **New** |
| `test_tsu_tx_l2_ptp_sync` | FC4.1, FC4.3, FC4.4 | **New** |
| `test_tsu_tx_queue_reset` | FC4.5, FC6.4 | **New** |
| `test_tsu_queue_overflow` | FC6.5 | **New** |

### Layer 4: CDC and Reset (new)

| Test | Coverage Points | Status |
|------|----------------|--------|
| `test_reset_clears_state` | FC6.1 | Existing |
| `test_cdc_time_read_handshake` | FC5.1 | **New** |

### Layer 5: X-propagation (formal)

| Check | Coverage Points | Method |
|-------|----------------|--------|
| xprop regression | All outputs X-free after reset | VC Formal xprop |

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

---

## X-propagation (Xprop)

X-propagation analysis is run via VC Formal to verify that no X-state can
propagate from any input to any output after a valid reset sequence. This is
critical for ASIC sign-off to ensure no silicon surprises from uninitialised
flip-flops or undriven nets.

Covered in `formal/ha1588_ahb/xprop.tcl`.
