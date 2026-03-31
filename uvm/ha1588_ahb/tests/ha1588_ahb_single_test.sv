///////////////////////////////////////////////////////////////////////////////
// ha1588_ahb_single_test.sv
///////////////////////////////////////////////////////////////////////////////
// Tests single-beat AHB register access through the ha1588_ahb wrapper.
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_HA1588_AHB_SINGLE_TEST_SV
`define GUARD_HA1588_AHB_SINGLE_TEST_SV

class ha1588_ahb_single_test extends ha1588_ahb_base_test;

  `uvm_component_utils(ha1588_ahb_single_test)

  function new(string name = "ha1588_ahb_single_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task main_phase(uvm_phase phase);
    ahb_single_write_sequence wr_seq;
    ahb_single_read_sequence  rd_seq;
    ahb_write_read_sequence   wr_rd_seq;

    phase.raise_objection(this);

    `uvm_info("TEST", "=== HA1588 Single Transfer Test ===", UVM_LOW)

    // Test 1: Write scratch register
    `uvm_info("TEST", "Test 1: Write scratch register", UVM_LOW)
    wr_seq = ahb_single_write_sequence::type_id::create("wr_seq");
    wr_seq.addr = 32'h04;
    wr_seq.data = 32'hDEAD_BEEF;
    wr_seq.start(env.ahb_sys_env.master[0].sequencer);

    // Test 2: Read scratch register
    `uvm_info("TEST", "Test 2: Read scratch register", UVM_LOW)
    rd_seq = ahb_single_read_sequence::type_id::create("rd_seq");
    rd_seq.addr = 32'h04;
    rd_seq.start(env.ahb_sys_env.master[0].sequencer);

    // Test 3: Write-readback on multiple RW registers
    `uvm_info("TEST", "Test 3: Write-readback on RW registers", UVM_LOW)
    begin
      bit [31:0] rw_addrs[] = '{32'h04, 32'h10, 32'h14, 32'h18, 32'h1C,
                                 32'h20, 32'h24, 32'h28, 32'h2C, 32'h30};
      for (int i = 0; i < rw_addrs.size(); i++) begin
        wr_rd_seq = ahb_write_read_sequence::type_id::create("wr_rd_seq");
        wr_rd_seq.addr = rw_addrs[i];
        wr_rd_seq.data = 32'hA000_0000 + i;
        wr_rd_seq.start(env.ahb_sys_env.master[0].sequencer);
      end
    end

    // Test 4: Read all registers in address space
    `uvm_info("TEST", "Test 4: Read all registers", UVM_LOW)
    for (int a = 0; a < 32'h80; a += 4) begin
      rd_seq = ahb_single_read_sequence::type_id::create("rd_seq");
      rd_seq.addr = a;
      rd_seq.start(env.ahb_sys_env.master[0].sequencer);
    end

    repeat (20) @(posedge ahb_vif.hclk);

    phase.drop_objection(this);
  endtask

endclass

`endif
