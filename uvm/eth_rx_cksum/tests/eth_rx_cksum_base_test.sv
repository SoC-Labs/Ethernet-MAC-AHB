///////////////////////////////////////////////////////////////////////////////
// eth_rx_cksum_base_test.sv — base UVM test.
///////////////////////////////////////////////////////////////////////////////

class eth_rx_cksum_base_test extends uvm_test;
  `uvm_component_utils(eth_rx_cksum_base_test)

  eth_rx_cksum_env    env;
  eth_rx_cksum_config cfg;

  function new(string name = "eth_rx_cksum_base_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg = eth_rx_cksum_config::type_id::create("cfg");
    if (!uvm_config_db#(virtual eth_rx_cksum_if)::get(
          this, "", "vif", cfg.vif))
      `uvm_fatal("NOVIF", "eth_rx_cksum_if not in config_db")
    uvm_config_db#(eth_rx_cksum_config)::set(this, "*", "cfg", cfg);

    env = eth_rx_cksum_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // Hold reset for several cycles of both clocks, then release.
    cfg.vif.presetn    <= 1'b0;
    cfg.vif.mrx_rstn   <= 1'b0;
    cfg.vif.apb_psel   <= 1'b0;
    cfg.vif.apb_penable<= 1'b0;
    cfg.vif.mrxdv      <= 1'b0;
    cfg.vif.mrxerr     <= 1'b0;
    #200ns;
    cfg.vif.presetn    <= 1'b1;
    cfg.vif.mrx_rstn   <= 1'b1;
    repeat (10) @(posedge cfg.vif.pclk);

    phase.drop_objection(this);
  endtask
endclass
