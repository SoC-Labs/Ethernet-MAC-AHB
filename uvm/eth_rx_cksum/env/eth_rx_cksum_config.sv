///////////////////////////////////////////////////////////////////////////////
// eth_rx_cksum_config.sv — env configuration object.
///////////////////////////////////////////////////////////////////////////////

class eth_rx_cksum_config extends uvm_object;
  `uvm_object_utils(eth_rx_cksum_config)

  // Configured via the config DB from the TB.
  virtual eth_rx_cksum_if vif;

  // FIFO depth parameter (matches the RTL SNAPSHOT_FIFO_DEPTH).
  int unsigned snapshot_fifo_depth = 8;

  // Clock periods (ns) for informational coverage gating.
  int unsigned pclk_period_ns    = 20;
  int unsigned mrx_clk_period_ns = 40;

  function new(string name = "eth_rx_cksum_config");
    super.new(name);
  endfunction
endclass
