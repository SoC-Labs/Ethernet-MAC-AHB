///////////////////////////////////////////////////////////////////////////////
// ha1588_ahb_random_test.sv
///////////////////////////////////////////////////////////////////////////////
// Constrained-random test for the ha1588_ahb wrapper.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_HA1588_AHB_RANDOM_TEST_SV
`define GUARD_HA1588_AHB_RANDOM_TEST_SV

class ha1588_ahb_random_test extends ha1588_ahb_base_test;

  `uvm_component_utils(ha1588_ahb_random_test)

  function new(string name = "ha1588_ahb_random_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task main_phase(uvm_phase phase);
    ahb_mixed_sequence mixed_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", "=== HA1588 Random Test ===", UVM_LOW)

    mixed_seq = ahb_mixed_sequence::type_id::create("mixed_seq");
    mixed_seq.num_transfers = 200;
    mixed_seq.start(env.ahb_sys_env.master[0].sequencer);

    repeat (50) @(posedge ahb_vif.hclk);

    phase.drop_objection(this);
  endtask

endclass

`endif
