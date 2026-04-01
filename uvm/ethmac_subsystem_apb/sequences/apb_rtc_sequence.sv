///////////////////////////////////////////////////////////////////////////////
// apb_rtc_sequence.sv — RTC period load, time set, GET_TIME handshake
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_APB_RTC_SEQUENCE_SV
`define GUARD_APB_RTC_SEQUENCE_SV

class apb_rtc_sequence extends svt_apb_master_base_sequence;
  `uvm_object_utils(apb_rtc_sequence)

  // PTP register offsets (Port 1 base = 0x1000)
  localparam bit [31:0] PTP_RTC_CTRL   = 32'h1000;
  localparam bit [31:0] PTP_SCRATCH    = 32'h1004;
  localparam bit [31:0] PTP_TIME_SEC_H = 32'h1010;
  localparam bit [31:0] PTP_TIME_SEC_L = 32'h1014;
  localparam bit [31:0] PTP_TIME_NSC_H = 32'h1018;
  localparam bit [31:0] PTP_TIME_NSC_L = 32'h101C;
  localparam bit [31:0] PTP_PERIOD_H   = 32'h1020;
  localparam bit [31:0] PTP_PERIOD_L   = 32'h1024;

  // RTC_CTRL bits
  localparam bit [31:0] GET_TIME   = 32'h01;
  localparam bit [31:0] SET_PERIOD = 32'h04;
  localparam bit [31:0] SET_TIME   = 32'h08;

  function new(string name = "apb_rtc_sequence");
    super.new(name);
  endfunction

  // Helper: single APB write
  task apb_wr(bit [31:0] addr, bit [31:0] data);
    integer status;
    `uvm_create(req)
    status = req.randomize() with {
      xact_type == svt_apb_transaction::WRITE;
      address   == addr;
      data      == local::data;
      pstrb     == 4'hF;
    };
    if (!status) `uvm_fatal("SEQ", "Randomize failed")
    `uvm_send(req)
  endtask

  // Helper: single APB read
  task apb_rd(bit [31:0] addr, output bit [31:0] rdata);
    integer status;
    `uvm_create(req)
    status = req.randomize() with {
      xact_type == svt_apb_transaction::READ;
      address   == addr;
    };
    if (!status) `uvm_fatal("SEQ", "Randomize failed")
    `uvm_send(req)
    rdata = req.data;
  endtask

  virtual task body();
    bit [31:0] rdata;

    `uvm_info("RTC_SEQ", "Step 1: Load 8ns period", UVM_LOW)
    apb_wr(PTP_PERIOD_H, 32'h0000_0008);
    apb_wr(PTP_PERIOD_L, 32'h0000_0000);
    apb_wr(PTP_RTC_CTRL, SET_PERIOD);

    // Wait for CDC propagation
    repeat (30) begin
      `uvm_create(req)
      void'(req.randomize() with {
        xact_type == svt_apb_transaction::READ;
        address   == PTP_SCRATCH;
      });
      `uvm_send(req)
    end

    apb_wr(PTP_RTC_CTRL, 32'h0);

    `uvm_info("RTC_SEQ", "Step 2: Load specific time (10s, 0ns)", UVM_LOW)
    apb_wr(PTP_TIME_SEC_H, 32'h0000);
    apb_wr(PTP_TIME_SEC_L, 32'h0000_000A);
    apb_wr(PTP_TIME_NSC_H, 32'h0000_0000);
    apb_wr(PTP_TIME_NSC_L, 32'h0000_0000);
    apb_wr(PTP_RTC_CTRL, SET_TIME);

    // Wait for CDC
    repeat (30) begin
      `uvm_create(req)
      void'(req.randomize() with {
        xact_type == svt_apb_transaction::READ;
        address   == PTP_SCRATCH;
      });
      `uvm_send(req)
    end

    apb_wr(PTP_RTC_CTRL, 32'h0);

    // Let RTC accumulate time
    repeat (100) begin
      `uvm_create(req)
      void'(req.randomize() with {
        xact_type == svt_apb_transaction::READ;
        address   == PTP_SCRATCH;
      });
      `uvm_send(req)
    end

    `uvm_info("RTC_SEQ", "Step 3: GET_TIME and verify", UVM_LOW)
    apb_wr(PTP_RTC_CTRL, GET_TIME);

    // Poll time_ok (bit 0 of RTC_CTRL readback)
    for (int i = 0; i < 50; i++) begin
      apb_rd(PTP_RTC_CTRL, rdata);
      if (rdata[0]) break;
    end

    // Read time registers
    apb_rd(PTP_TIME_SEC_L, rdata);
    `uvm_info("RTC_SEQ", $sformatf("RTC seconds = 0x%08h (expect >= 0xA)", rdata), UVM_LOW)
    if (rdata < 32'hA)
      `uvm_error("RTC_SEQ", $sformatf("Seconds (%0d) < 10 after time load", rdata))

    apb_rd(PTP_TIME_NSC_H, rdata);
    `uvm_info("RTC_SEQ", $sformatf("RTC ns = 0x%08h (expect > 0)", rdata), UVM_LOW)

    apb_wr(PTP_RTC_CTRL, 32'h0);
  endtask
endclass

`endif
