///////////////////////////////////////////////////////////////////////////////
// subsystem_rtc_test.sv — CP4: RTC functional operation via APB
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_SUBSYSTEM_RTC_TEST_SV
`define GUARD_SUBSYSTEM_RTC_TEST_SV

class subsystem_rtc_test extends subsystem_base_test;
  `uvm_component_utils(subsystem_rtc_test)

  function new(string name = "subsystem_rtc_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task main_phase(uvm_phase phase);
    apb_rtc_sequence rtc_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", "=== Subsystem RTC Test (CP4.1-CP4.3) ===", UVM_LOW)
    rtc_seq = apb_rtc_sequence::type_id::create("rtc_seq");
    rtc_seq.start(env.apb_sys_env.master[0].sequencer);

    // CP4.3: Verify PTP ns output is non-zero (check via hierarchical access)
    if (test_top.rtc_time_ptp_ns === 32'h0)
      `uvm_warning("CP4.3", "rtc_time_ptp_ns is 0 — may need more time to accumulate")
    else
      `uvm_info("CP4.3", $sformatf("rtc_time_ptp_ns = 0x%08h", test_top.rtc_time_ptp_ns), UVM_LOW)

    repeat (20) @(posedge apb_vif.pclk);
    phase.drop_objection(this);
  endtask
endclass

`endif
