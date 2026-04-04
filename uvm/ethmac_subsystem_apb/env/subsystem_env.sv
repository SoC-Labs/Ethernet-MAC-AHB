///////////////////////////////////////////////////////////////////////////////
// subsystem_env.sv — Top-level UVM environment
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_SUBSYSTEM_ENV_SV
`define GUARD_SUBSYSTEM_ENV_SV

class subsystem_env extends uvm_env;
  `uvm_component_utils(subsystem_env)

  svt_apb_system_env      apb_sys_env;
  svt_ahb_system_env      ahb_sys_env;
  subsystem_scoreboard    sb;
  subsystem_coverage      cov;
  subsystem_apb_config    apb_cfg;
  subsystem_ahb_config    ahb_cfg;

  function new(string name = "subsystem_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(subsystem_apb_config)::get(this, "", "apb_cfg", apb_cfg))
      apb_cfg = subsystem_apb_config::type_id::create("apb_cfg");
    if (!uvm_config_db#(subsystem_ahb_config)::get(this, "", "ahb_cfg", ahb_cfg))
      ahb_cfg = subsystem_ahb_config::type_id::create("ahb_cfg");

    uvm_config_db#(svt_apb_system_configuration)::set(this, "apb_sys_env", "cfg", apb_cfg);
    uvm_config_db#(svt_ahb_system_configuration)::set(this, "ahb_sys_env", "cfg", ahb_cfg);

    apb_sys_env = svt_apb_system_env::type_id::create("apb_sys_env", this);
    ahb_sys_env = svt_ahb_system_env::type_id::create("ahb_sys_env", this);
    sb          = subsystem_scoreboard::type_id::create("sb", this);
    cov         = subsystem_coverage::type_id::create("cov", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    apb_sys_env.master.monitor.item_observed_port.connect(sb.apb_export);
    apb_sys_env.master.monitor.item_observed_port.connect(cov.apb_export);
  endfunction
endclass

`endif
