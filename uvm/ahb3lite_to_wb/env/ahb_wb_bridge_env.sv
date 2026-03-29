///////////////////////////////////////////////////////////////////////////////
// ahb_wb_bridge_env.sv
///////////////////////////////////////////////////////////////////////////////
// Top-level UVM environment for the ahb3lite_to_wb bridge testbench.
//
// Contains:
//   - Synopsys VIP AHB system environment (active master + passive slave monitor)
//   - Custom Wishbone slave agent (active, responds to DUT WB master outputs)
//   - Scoreboard comparing AHB and WB transactions
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_AHB_WB_BRIDGE_ENV_SV
`define GUARD_AHB_WB_BRIDGE_ENV_SV

class ahb_wb_bridge_env extends uvm_env;

  `uvm_component_utils(ahb_wb_bridge_env)

  // Components
  svt_ahb_system_env       ahb_sys_env;
  wb_slave_agent           wb_agt;
  ahb_wb_bridge_scoreboard sb;

  // Configuration
  ahb_wb_bridge_config     cfg;

  function new(string name = "ahb_wb_bridge_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    `uvm_info("build_phase", "Building ahb_wb_bridge_env...", UVM_LOW)

    // Create or get configuration
    if (!uvm_config_db#(ahb_wb_bridge_config)::get(this, "", "cfg", cfg)) begin
      cfg = ahb_wb_bridge_config::type_id::create("cfg");
    end

    // Pass AHB system configuration to VIP system env
    uvm_config_db#(svt_ahb_system_configuration)::set(this, "ahb_sys_env", "cfg", cfg);

    // Create components
    ahb_sys_env = svt_ahb_system_env::type_id::create("ahb_sys_env", this);
    wb_agt      = wb_slave_agent::type_id::create("wb_agt", this);
    sb          = ahb_wb_bridge_scoreboard::type_id::create("sb", this);

    `uvm_info("build_phase", "Build complete.", UVM_LOW)
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Connect VIP active master monitor -> scoreboard
    ahb_sys_env.master[0].monitor.item_observed_port.connect(sb.ahb_export);

    // Connect WB slave monitor -> scoreboard
    wb_agt.ap.connect(sb.wb_export);
  endfunction

endclass

`endif // GUARD_AHB_WB_BRIDGE_ENV_SV
