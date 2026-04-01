///////////////////////////////////////////////////////////////////////////////
// apb_dma_tx_sequence.sv — Configure MAC and trigger a TX DMA transfer
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_APB_DMA_TX_SEQUENCE_SV
`define GUARD_APB_DMA_TX_SEQUENCE_SV

class apb_dma_tx_sequence extends svt_apb_master_base_sequence;
  `uvm_object_utils(apb_dma_tx_sequence)

  // ETH register offsets (Port 0 base = 0x0000)
  localparam bit [31:0] ETH_MODER      = 32'h0000;
  localparam bit [31:0] ETH_INT_SOURCE = 32'h0004;
  localparam bit [31:0] ETH_INT_MASK   = 32'h0008;
  localparam bit [31:0] ETH_IPGT       = 32'h000C;
  localparam bit [31:0] ETH_IPGR1      = 32'h0010;
  localparam bit [31:0] ETH_IPGR2      = 32'h0014;
  localparam bit [31:0] ETH_PACKETLEN  = 32'h0018;
  localparam bit [31:0] ETH_TX_BD_NUM  = 32'h0020;
  localparam bit [31:0] ETH_MAC_ADDR0  = 32'h0040;
  localparam bit [31:0] ETH_MAC_ADDR1  = 32'h0044;
  localparam bit [31:0] ETH_BD_BASE    = 32'h0400;

  // MODER bits
  localparam bit [31:0] MODER_TXEN  = 32'h0002;
  localparam bit [31:0] MODER_FULLD = 32'h0400;
  localparam bit [31:0] MODER_CRCEN = 32'h2000;
  localparam bit [31:0] MODER_PAD   = 32'h8000;

  // TX BD bits
  localparam bit [15:0] TX_BD_RD  = 16'h8000;
  localparam bit [15:0] TX_BD_IRQ = 16'h4000;
  localparam bit [15:0] TX_BD_WR  = 16'h2000;
  localparam bit [15:0] TX_BD_PAD = 16'h1000;
  localparam bit [15:0] TX_BD_CRC = 16'h0800;

  function new(string name = "apb_dma_tx_sequence");
    super.new(name);
  endfunction

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
    bit [31:0] bd_word0;

    `uvm_info("DMA_TX", "Step 1: Configure MAC", UVM_LOW)

    // MAC address
    apb_wr(ETH_MAC_ADDR0, 32'hEFBEADDE);
    apb_wr(ETH_MAC_ADDR1, 32'h0000_0002);

    // Timing parameters
    apb_wr(ETH_IPGT,  32'h15);
    apb_wr(ETH_IPGR1, 32'h0C);
    apb_wr(ETH_IPGR2, 32'h12);
    apb_wr(ETH_PACKETLEN, 32'h05EE_0040);  // max=1518, min=64

    // 2 TX BDs
    apb_wr(ETH_TX_BD_NUM, 32'h0002);

    // Enable TX interrupt
    apb_wr(ETH_INT_MASK, 32'h0001);

    `uvm_info("DMA_TX", "Step 2: Setup TX BD", UVM_LOW)

    // TX BD 0: 60 bytes, ready, IRQ, wrap, PAD, CRC
    // Buffer at AHB address 0x0000 (AHB slave VIP memory model)
    bd_word0 = {16'h003C, TX_BD_RD | TX_BD_IRQ | TX_BD_WR | TX_BD_PAD | TX_BD_CRC};
    apb_wr(ETH_BD_BASE,     bd_word0);
    apb_wr(ETH_BD_BASE + 4, 32'h0000_0000);  // Buffer address

    `uvm_info("DMA_TX", "Step 3: Enable TX", UVM_LOW)

    // MODER: TXEN + FULLD + CRCEN + PAD
    apb_wr(ETH_MODER, 32'h0000_A000 | MODER_TXEN | MODER_FULLD | MODER_CRCEN | MODER_PAD);

    `uvm_info("DMA_TX", "Step 4: Poll TX BD for completion", UVM_LOW)

    // Poll until TX BD RD bit clears (transmission complete)
    for (int i = 0; i < 500; i++) begin
      apb_rd(ETH_BD_BASE, rdata);
      if (!(rdata & {16'h0, TX_BD_RD})) begin
        `uvm_info("DMA_TX", $sformatf("TX complete after %0d polls, BD=0x%08h", i, rdata), UVM_LOW)
        break;
      end
    end

    if (rdata & {16'h0, TX_BD_RD})
      `uvm_error("DMA_TX", "TX BD RD bit never cleared — DMA TX did not complete")

    // Check interrupt source
    apb_rd(ETH_INT_SOURCE, rdata);
    `uvm_info("DMA_TX", $sformatf("INT_SOURCE = 0x%08h", rdata), UVM_LOW)
    if (!(rdata & 32'h1))
      `uvm_warning("DMA_TX", "INT_SOURCE TXB not set (may depend on AHB slave memory content)")

    // Clear interrupt
    apb_wr(ETH_INT_SOURCE, rdata);

    // Disable MAC
    apb_wr(ETH_MODER, 32'h0000_A000);
  endtask
endclass

`endif
