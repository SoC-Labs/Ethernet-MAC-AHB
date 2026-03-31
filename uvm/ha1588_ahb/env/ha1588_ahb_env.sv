///////////////////////////////////////////////////////////////////////////////
// ha1588_ahb_env.sv
///////////////////////////////////////////////////////////////////////////////
// Top-level UVM environment for the ha1588_ahb testbench.
//
// Contains:
//   - Synopsys VIP AHB system environment (active master + passive slave)
//   - Scoreboard for register write-readback verification
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_HA1588_AHB_ENV_SV
`define GUARD_HA1588_AHB_ENV_SV

class ha1588_ahb_env extends uvm_env;

  `uvm_component_utils(ha1588_ahb_env)

  svt_ahb_system_env       ahb_sys_env;
  ha1588_ahb_scoreboard    sb;
  ha1588_ahb_config        cfg;

  function new(string name = "ha1588_ahb_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    `uvm_info("build_phase", "Building ha1588_ahb_env...", UVM_LOW)

    if (!uvm_config_db#(ha1588_ahb_config)::get(this, "", "cfg", cfg)) begin
      cfg = ha1588_ahb_config::type_id::create("cfg");
    end

    uvm_config_db#(svt_ahb_system_configuration)::set(this, "ahb_sys_env", "cfg", cfg);

    ahb_sys_env = svt_ahb_system_env::type_id::create("ahb_sys_env", this);
    sb          = ha1588_ahb_scoreboard::type_id::create("sb", this);

    `uvm_info("build_phase", "Build complete.", UVM_LOW)
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Connect VIP active master monitor -> scoreboard
    ahb_sys_env.master[0].monitor.item_observed_port.connect(sb.ahb_export);
  endfunction

endclass

`endif // GUARD_HA1588_AHB_ENV_SV
