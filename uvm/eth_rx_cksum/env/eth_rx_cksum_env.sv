///////////////////////////////////////////////////////////////////////////////
// eth_rx_cksum_env.sv — top-level UVM env.
//
// This env bundles:
//   - an APB master driver task group (simple native, not VC-VIP)
//   - an MII source task group that emits nibble-level frames
//   - the coverage model
//
// Agent/driver/monitor separation is intentionally light for this block —
// it's a single APB slave with a single RX stream, so the full UVC-style
// agent split would be over-engineered. Wrapper tasks on the virtual
// interface give sequences all the API they need.
///////////////////////////////////////////////////////////////////////////////

class eth_rx_cksum_env extends uvm_env;
  `uvm_component_utils(eth_rx_cksum_env)

  eth_rx_cksum_config   cfg;
  eth_rx_cksum_coverage cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(eth_rx_cksum_config)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "eth_rx_cksum_config not set in config_db")

    cov = eth_rx_cksum_coverage::type_id::create("cov", this);
  endfunction

  // ── APB master helpers ────────────────────────────────────────────────
  task apb_write(input logic [11:0] addr, input logic [31:0] data);
    @(posedge cfg.vif.pclk);
    cfg.vif.apb_psel    <= 1'b1;
    cfg.vif.apb_penable <= 1'b0;
    cfg.vif.apb_paddr   <= {20'h0, addr};
    cfg.vif.apb_pwrite  <= 1'b1;
    cfg.vif.apb_pwdata  <= data;
    cfg.vif.apb_pstrb   <= 4'hF;
    @(posedge cfg.vif.pclk);
    cfg.vif.apb_penable <= 1'b1;
    @(posedge cfg.vif.pclk);
    cfg.vif.apb_psel    <= 1'b0;
    cfg.vif.apb_penable <= 1'b0;
    cfg.vif.apb_pwrite  <= 1'b0;
  endtask

  task apb_read(input logic [11:0] addr, output logic [31:0] data);
    @(posedge cfg.vif.pclk);
    cfg.vif.apb_psel    <= 1'b1;
    cfg.vif.apb_penable <= 1'b0;
    cfg.vif.apb_paddr   <= {20'h0, addr};
    cfg.vif.apb_pwrite  <= 1'b0;
    cfg.vif.apb_pstrb   <= 4'hF;
    @(posedge cfg.vif.pclk);
    cfg.vif.apb_penable <= 1'b1;
    @(posedge cfg.vif.pclk);
    data = cfg.vif.apb_prdata;
    cfg.vif.apb_psel    <= 1'b0;
    cfg.vif.apb_penable <= 1'b0;
  endtask

  // ── MII source ────────────────────────────────────────────────────────
  // Drives preamble + SFD + frame_bytes + 4 zero bytes (placeholder FCS,
  // not validated by the block).
  task mii_send_frame(input byte unsigned frame_bytes[]);
    byte unsigned preamble[] = '{'h55,'h55,'h55,'h55,'h55,'h55,'h55,'hD5};
    byte unsigned fcs[]      = '{0,0,0,0};
    int n = preamble.size() + frame_bytes.size() + fcs.size();
    byte unsigned full[];
    full = new[n];
    foreach (preamble[i])     full[i] = preamble[i];
    foreach (frame_bytes[i])  full[preamble.size()+i] = frame_bytes[i];
    foreach (fcs[i])          full[preamble.size()+frame_bytes.size()+i] = fcs[i];

    @(negedge cfg.vif.mrx_clk);
    foreach (full[i]) begin
      cfg.vif.mrxd  <= full[i][3:0];
      cfg.vif.mrxdv <= 1'b1;
      @(negedge cfg.vif.mrx_clk);
      cfg.vif.mrxd  <= full[i][7:4];
      cfg.vif.mrxdv <= 1'b1;
      @(negedge cfg.vif.mrx_clk);
    end
    cfg.vif.mrxd  <= 4'h0;
    cfg.vif.mrxdv <= 1'b0;
    // Inter-frame gap — 12 bytes minimum → 24 mrx_clks
    repeat (24) @(negedge cfg.vif.mrx_clk);
  endtask

endclass
