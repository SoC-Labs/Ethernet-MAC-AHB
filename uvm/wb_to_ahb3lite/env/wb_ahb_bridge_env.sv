///////////////////////////////////////////////////////////////////////////////
// wb_ahb_bridge_env.sv
///////////////////////////////////////////////////////////////////////////////
// Top-level UVM environment for the wb_to_ahb3lite bridge testbench.
//
// Contains:
//   - Custom Wishbone master agent (active, drives stimulus)
//   - Synopsys VIP AHB system environment (passive master monitor + active slave)
//   - Scoreboard comparing WB and AHB transactions
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_WB_AHB_BRIDGE_ENV_SV
`define GUARD_WB_AHB_BRIDGE_ENV_SV

class wb_ahb_bridge_env extends uvm_env;

  `uvm_component_utils(wb_ahb_bridge_env)

  // Components
  wb_master_agent          wb_agt;
  svt_ahb_system_env       ahb_sys_env;
  wb_ahb_bridge_scoreboard sb;

  // Configuration
  wb_ahb_bridge_config     cfg;

  function new(string name = "wb_ahb_bridge_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    `uvm_info("build_phase", "Building wb_ahb_bridge_env...", UVM_LOW)

    // Create or get configuration
    if (!uvm_config_db#(wb_ahb_bridge_config)::get(this, "", "cfg", cfg)) begin
      cfg = wb_ahb_bridge_config::type_id::create("cfg");
    end

    // Pass AHB system configuration to VIP system env
    uvm_config_db#(svt_ahb_system_configuration)::set(this, "ahb_sys_env", "cfg", cfg);

    // Create components
    wb_agt      = wb_master_agent::type_id::create("wb_agt", this);
    ahb_sys_env = svt_ahb_system_env::type_id::create("ahb_sys_env", this);
    sb          = wb_ahb_bridge_scoreboard::type_id::create("sb", this);

    `uvm_info("build_phase", "Build complete.", UVM_LOW)
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Connect WB monitor -> scoreboard
    wb_agt.ap.connect(sb.wb_export);

    // Connect VIP passive master monitor -> scoreboard
    ahb_sys_env.master[0].monitor.item_observed_port.connect(sb.ahb_export);
  endfunction

endclass

`endif // GUARD_WB_AHB_BRIDGE_ENV_SV
