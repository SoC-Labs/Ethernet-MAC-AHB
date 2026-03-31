///////////////////////////////////////////////////////////////////////////////
// subsystem_config.sv — APB + AHB VIP configuration
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_SUBSYSTEM_CONFIG_SV
`define GUARD_SUBSYSTEM_CONFIG_SV

// APB system configuration: 1 active master, 1 passive slave
class subsystem_apb_config extends svt_apb_system_configuration;
  `uvm_object_utils(subsystem_apb_config)

  function new(string name = "subsystem_apb_config");
    super.new(name);
    this.num_masters         = 1;
    this.num_slaves          = 1;
    this.create_sub_cfgs(1, 1);
    this.master_cfg[0].is_active = 1;
    this.slave_cfg[0].is_active  = 0;
    this.set_addr_range(0, 32'h0000_0000, 32'h0000_1FFF);
    this.master_cfg[0].enable_xml_gen = 0;
    this.slave_cfg[0].enable_xml_gen  = 0;
  endfunction
endclass

// AHB system configuration: 1 passive master (observe DUT), 1 active slave (respond)
class subsystem_ahb_config extends svt_ahb_system_configuration;
  `uvm_object_utils(subsystem_ahb_config)

  function new(string name = "subsystem_ahb_config");
    super.new(name);
    this.num_masters = 1;
    this.num_slaves  = 1;
    this.create_sub_cfgs(1, 1);
    this.master_cfg[0].is_active          = 0;  // passive — observe DUT master
    this.master_cfg[0].data_width         = 32;
    this.slave_cfg[0].is_active           = 1;  // active — respond to DUT
    this.slave_cfg[0].data_width          = 32;
    this.slave_cfg[0].mem_enable          = 1;  // built-in memory model
    this.ahb_lite = 1;
    this.set_addr_range(0, 32'h0000_0000, 32'hFFFF_FFFF);
    this.master_cfg[0].enable_xml_gen = 0;
    this.slave_cfg[0].enable_xml_gen  = 0;
  endfunction
endclass

`endif
