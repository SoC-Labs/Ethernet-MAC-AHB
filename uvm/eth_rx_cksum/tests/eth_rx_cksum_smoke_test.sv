///////////////////////////////////////////////////////////////////////////////
// eth_rx_cksum_smoke_test.sv — smoke test: ID, CTRL, one IPv4/UDP frame.
///////////////////////////////////////////////////////////////////////////////

class eth_rx_cksum_smoke_test extends eth_rx_cksum_base_test;
  `uvm_component_utils(eth_rx_cksum_smoke_test)

  function new(string name = "eth_rx_cksum_smoke_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    eth_rx_cksum_basic_seq seq;

    phase.raise_objection(this);

    // Reset handshake (inherited from base_test doesn't raise/drop here —
    // just drive directly).
    cfg.vif.presetn    <= 1'b0;
    cfg.vif.mrx_rstn   <= 1'b0;
    cfg.vif.apb_psel   <= 1'b0;
    cfg.vif.apb_penable<= 1'b0;
    cfg.vif.mrxdv      <= 1'b0;
    cfg.vif.mrxerr     <= 1'b0;
    #200ns;
    cfg.vif.presetn    <= 1'b1;
    cfg.vif.mrx_rstn   <= 1'b1;
    repeat (20) @(posedge cfg.vif.pclk);

    seq     = eth_rx_cksum_basic_seq::type_id::create("seq");
    seq.env = env;
    seq.start(null);

    repeat (50) @(posedge cfg.vif.pclk);
    phase.drop_objection(this);
  endtask
endclass
