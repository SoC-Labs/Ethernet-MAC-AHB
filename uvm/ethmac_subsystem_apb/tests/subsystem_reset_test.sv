///////////////////////////////////////////////////////////////////////////////
// subsystem_reset_test.sv — CP8: Reset behaviour
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_SUBSYSTEM_RESET_TEST_SV
`define GUARD_SUBSYSTEM_RESET_TEST_SV

class subsystem_reset_test extends subsystem_base_test;
  `uvm_component_utils(subsystem_reset_test)

  function new(string name = "subsystem_reset_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task main_phase(uvm_phase phase);
    apb_write_sequence wr_seq;
    apb_read_sequence  rd_seq;

    phase.raise_objection(this);

    // ── CP8.2: int_o deasserted after reset ──
    `uvm_info("TEST", "CP8.2: Verify int_o = 0", UVM_LOW)
    if (dut_if.int_o !== 1'b0)
      `uvm_error("CP8.2", "int_o not 0 after reset")

    // ── CP8.3: AHB master idle after reset ──
    `uvm_info("TEST", "CP8.3: Verify htrans = IDLE", UVM_LOW)
    if (dut_if.htrans !== 2'b00)
      `uvm_error("CP8.3", $sformatf("htrans = %0b after reset", dut_if.htrans))

    // ── CP8.1: Write, reset, verify defaults ──
    `uvm_info("TEST", "CP8.1: Write then reset then check defaults", UVM_LOW)
    wr_seq = apb_write_sequence::type_id::create("wr_seq");
    wr_seq.addr = 32'h0008; wr_seq.data = 32'h7F;
    wr_seq.start(env.apb_sys_env.master.sequencer);

    // Assert reset
    dut_if.assert_reset();
    repeat (10) @(posedge apb_vif.pclk);
    dut_if.deassert_reset();
    repeat (10) @(posedge apb_vif.pclk);

    // Read MODER default
    rd_seq = apb_read_sequence::type_id::create("rd_seq");
    rd_seq.addr = 32'h0000;
    rd_seq.start(env.apb_sys_env.master.sequencer);

    if (rd_seq.rdata !== 32'h0000A000)
      `uvm_error("CP8.1", $sformatf("MODER after reset = 0x%08h", rd_seq.rdata))

    // Read INT_MASK should be 0
    rd_seq = apb_read_sequence::type_id::create("rd_seq");
    rd_seq.addr = 32'h0008;
    rd_seq.start(env.apb_sys_env.master.sequencer);

    if (rd_seq.rdata !== 32'h0)
      `uvm_error("CP8.1", $sformatf("INT_MASK after reset = 0x%08h", rd_seq.rdata))

    repeat (20) @(posedge apb_vif.pclk);
    phase.drop_objection(this);
  endtask
endclass

`endif
