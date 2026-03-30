///////////////////////////////////////////////////////////////////////////////
// rmii_mii_env.sv
///////////////////////////////////////////////////////////////////////////////
// Top-level UVM environment for the rmii_to_mii adapter testbench.
//
// Contains:
//   - MII agent  (active TX driver + passive RX monitor)
//   - RMII agent (active RX driver + passive TX monitor)
//   - Scoreboard comparing both data paths
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_RMII_MII_ENV_SV
`define GUARD_RMII_MII_ENV_SV

class rmii_mii_env extends uvm_env;

  `uvm_component_utils(rmii_mii_env)

  mii_agent            mii_agt;
  rmii_agent           rmii_agt;
  rmii_mii_scoreboard  sb;
  rmii_mii_config      cfg;

  function new(string name = "rmii_mii_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    `uvm_info("build_phase", "Building rmii_mii_env...", UVM_LOW)

    if (!uvm_config_db#(rmii_mii_config)::get(this, "", "cfg", cfg)) begin
      cfg = rmii_mii_config::type_id::create("cfg");
    end

    mii_agt  = mii_agent::type_id::create("mii_agt", this);
    rmii_agt = rmii_agent::type_id::create("rmii_agt", this);
    sb       = rmii_mii_scoreboard::type_id::create("sb", this);

    `uvm_info("build_phase", "Build complete.", UVM_LOW)
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // TX path: MII driver (reference) → scoreboard, RMII monitor (actual) → scoreboard
    mii_agt.tx_ap.connect(sb.mii_tx_export);
    rmii_agt.tx_ap.connect(sb.rmii_tx_export);

    // RX path: RMII driver (reference) → scoreboard, MII monitor (actual) → scoreboard
    rmii_agt.rx_ap.connect(sb.rmii_rx_export);
    mii_agt.rx_ap.connect(sb.mii_rx_export);
  endfunction

endclass

`endif // GUARD_RMII_MII_ENV_SV
