///////////////////////////////////////////////////////////////////////////////
// subsystem_register_test.sv — Covers CP1, CP2, CP3 (register access)
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_SUBSYSTEM_REGISTER_TEST_SV
`define GUARD_SUBSYSTEM_REGISTER_TEST_SV

class subsystem_register_test extends subsystem_base_test;
  `uvm_component_utils(subsystem_register_test)

  function new(string name = "subsystem_register_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task main_phase(uvm_phase phase);
    apb_write_sequence     wr_seq;
    apb_read_sequence      rd_seq;
    apb_write_read_sequence wr_rd_seq;

    phase.raise_objection(this);

    // ── CP1.1 / CP2.1: ETH MODER default ──
    `uvm_info("TEST", "CP2.1: Read MODER default", UVM_LOW)
    rd_seq = apb_read_sequence::type_id::create("rd_seq");
    rd_seq.addr = 32'h0000;
    rd_seq.start(env.apb_sys_env.master.sequencer);

    // ── CP1.2 / CP3.1: PTP scratch write-read ──
    `uvm_info("TEST", "CP3.1: PTP scratch write-read", UVM_LOW)
    wr_rd_seq = apb_write_read_sequence::type_id::create("wr_rd_seq");
    wr_rd_seq.addr = 32'h1004;
    wr_rd_seq.data = 32'hDEADBEEF;
    wr_rd_seq.start(env.apb_sys_env.master.sequencer);

    // ── CP2.2: ETH MODER write-readback ──
    `uvm_info("TEST", "CP2.2: MODER write-readback", UVM_LOW)
    wr_rd_seq = apb_write_read_sequence::type_id::create("wr_rd_seq");
    wr_rd_seq.addr = 32'h0000;
    wr_rd_seq.data = 32'h0000E003;
    wr_rd_seq.start(env.apb_sys_env.master.sequencer);

    // ── CP2.3: INT_MASK ──
    wr_rd_seq = apb_write_read_sequence::type_id::create("wr_rd_seq");
    wr_rd_seq.addr = 32'h0008;
    wr_rd_seq.data = 32'h0000007F;
    wr_rd_seq.start(env.apb_sys_env.master.sequencer);

    // ── CP2.4: MAC address ──
    wr_rd_seq = apb_write_read_sequence::type_id::create("wr_rd_seq");
    wr_rd_seq.addr = 32'h0040;
    wr_rd_seq.data = 32'hDEADBEEF;
    wr_rd_seq.start(env.apb_sys_env.master.sequencer);

    wr_rd_seq = apb_write_read_sequence::type_id::create("wr_rd_seq");
    wr_rd_seq.addr = 32'h0044;
    wr_rd_seq.data = 32'h00001234;
    wr_rd_seq.start(env.apb_sys_env.master.sequencer);

    // ── CP2.5: Buffer descriptor ──
    wr_rd_seq = apb_write_read_sequence::type_id::create("wr_rd_seq");
    wr_rd_seq.addr = 32'h0400;
    wr_rd_seq.data = 32'h12345678;
    wr_rd_seq.start(env.apb_sys_env.master.sequencer);

    // ── CP2.6: Walking ones on HASH0 ──
    `uvm_info("TEST", "CP2.6: Walking ones on HASH0", UVM_LOW)
    for (int i = 0; i < 32; i++) begin
      wr_rd_seq = apb_write_read_sequence::type_id::create("wr_rd_seq");
      wr_rd_seq.addr = 32'h0048;
      wr_rd_seq.data = (32'h1 << i);
      wr_rd_seq.start(env.apb_sys_env.master.sequencer);
    end

    // ── CP1.3: Interleaved access ──
    `uvm_info("TEST", "CP1.3: Interleaved ETH/PTP access", UVM_LOW)
    wr_rd_seq = apb_write_read_sequence::type_id::create("wr_rd_seq");
    wr_rd_seq.addr = 32'h004C; wr_rd_seq.data = 32'h11111111;
    wr_rd_seq.start(env.apb_sys_env.master.sequencer);

    wr_rd_seq = apb_write_read_sequence::type_id::create("wr_rd_seq");
    wr_rd_seq.addr = 32'h1020; wr_rd_seq.data = 32'h00000008;
    wr_rd_seq.start(env.apb_sys_env.master.sequencer);

    // ── CP3.2–CP3.5: PTP register coverage ──
    begin
      bit [31:0] ptp_addrs[] = '{32'h1010, 32'h1014, 32'h1018, 32'h101C,
                                  32'h1024, 32'h1028, 32'h102C, 32'h1030};
      for (int i = 0; i < ptp_addrs.size(); i++) begin
        wr_rd_seq = apb_write_read_sequence::type_id::create("wr_rd_seq");
        wr_rd_seq.addr = ptp_addrs[i];
        wr_rd_seq.data = 32'hA0000000 + i;
        wr_rd_seq.start(env.apb_sys_env.master.sequencer);
      end
    end

    // ── CP3.5: TSU message ID mask ──
    wr_seq = apb_write_sequence::type_id::create("wr_seq");
    wr_seq.addr = 32'h1044; wr_seq.data = 32'hFF000000;
    wr_seq.start(env.apb_sys_env.master.sequencer);
    rd_seq = apb_read_sequence::type_id::create("rd_seq");
    rd_seq.addr = 32'h1044;
    rd_seq.start(env.apb_sys_env.master.sequencer);

    // ── CP3.6: Walking ones on PTP scratch ──
    `uvm_info("TEST", "CP3.6: Walking ones on PTP scratch", UVM_LOW)
    for (int i = 0; i < 32; i++) begin
      wr_rd_seq = apb_write_read_sequence::type_id::create("wr_rd_seq");
      wr_rd_seq.addr = 32'h1004;
      wr_rd_seq.data = (32'h1 << i);
      wr_rd_seq.start(env.apb_sys_env.master.sequencer);
    end

    // ── CP1.4: Disabled port ──
    `uvm_info("TEST", "CP1.4: Access disabled port", UVM_LOW)
    rd_seq = apb_read_sequence::type_id::create("rd_seq");
    rd_seq.addr = 32'h2000;
    rd_seq.start(env.apb_sys_env.master.sequencer);

    repeat (20) @(posedge apb_vif.pclk);
    phase.drop_objection(this);
  endtask
endclass

`endif
