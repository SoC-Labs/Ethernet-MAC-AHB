///////////////////////////////////////////////////////////////////////////////
// ha1588_ahb_config.sv
///////////////////////////////////////////////////////////////////////////////
// SVT AHB system configuration for the ha1588_ahb testbench.
//
// The DUT is the AHB slave, so:
//   - VIP master[0] is ACTIVE  (drives AHB master stimulus to DUT)
//   - VIP slave[0]  is PASSIVE (monitors DUT's AHB slave responses)
///////////////////////////////////////////////////////////////////////////////

`ifndef GUARD_HA1588_AHB_CONFIG_SV
`define GUARD_HA1588_AHB_CONFIG_SV

class ha1588_ahb_config extends svt_ahb_system_configuration;

  `uvm_object_utils(ha1588_ahb_config)

  function new(string name = "ha1588_ahb_config");
    super.new(name);

    this.num_masters = 1;
    this.num_slaves  = 1;
    this.create_sub_cfgs(1, 1);

    // Master is active -- VIP drives AHB master signals to the DUT
    this.master_cfg[0].is_active = 1;
    this.master_cfg[0].data_width = 32;
    this.master_cfg[0].transaction_coverage_enable = 1;

    // Slave is passive -- DUT is the AHB slave, VIP only monitors
    this.slave_cfg[0].is_active = 0;
    this.slave_cfg[0].data_width = 32;
    this.slave_cfg[0].transaction_coverage_enable = 1;

    // AHB-Lite mode
    this.ahb_lite = 1;

    // HA1588 address space is 128 bytes (0x00-0x7F)
    this.set_addr_range(0, 32'h0000_0000, 32'h0000_007F);

    // Disable protocol file generation
    this.master_cfg[0].enable_xml_gen = 0;
    this.slave_cfg[0].enable_xml_gen  = 0;
  endfunction

endclass

`endif // GUARD_HA1588_AHB_CONFIG_SV
