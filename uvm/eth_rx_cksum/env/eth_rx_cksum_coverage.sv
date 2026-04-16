///////////////////////////////////////////////////////////////////////////////
// eth_rx_cksum_coverage.sv — functional coverage model.
//
// Samples a per-frame snapshot (populated by the scoreboard / monitor)
// and tracks crosses across:
//   - Protocol (IPv4, IPv6, VLAN, UDP, TCP)
//   - Frame length bucket (small / medium / jumbo)
//   - Result combinations (IP_OK / L4_OK / IP_FRAG)
//   - FIFO mode (LAST_ONLY, DROP_NEW, DROP_OLD)
//   - OVF sticky observed yes/no
//
// To run a coverage-closure campaign, bind the monitor's analysis port
// to the `sample()` method below and drive the random / protocol-mix
// sequences until all covered bins are hit.
///////////////////////////////////////////////////////////////////////////////

typedef enum bit [2:0] {
  FRAME_KIND_IPV4_UDP,
  FRAME_KIND_IPV4_TCP,
  FRAME_KIND_IPV4_OTHER,
  FRAME_KIND_IPV6_UDP,
  FRAME_KIND_IPV6_TCP,
  FRAME_KIND_NON_IP
} frame_kind_e;

typedef struct {
  frame_kind_e kind;
  bit          vlan;
  bit          ip_ok;
  bit          l4_ok;
  bit          ip_frag;
  bit [1:0]    mode;
  bit          ovf_seen;
  int unsigned frame_len;
} cksum_event_t;

class eth_rx_cksum_coverage extends uvm_component;
  `uvm_component_utils(eth_rx_cksum_coverage)

  cksum_event_t ev;

  covergroup cg_frame;
    option.per_instance = 1;

    cp_kind     : coverpoint ev.kind;
    cp_vlan     : coverpoint ev.vlan;
    cp_ip_ok    : coverpoint ev.ip_ok;
    cp_l4_ok    : coverpoint ev.l4_ok;
    cp_frag     : coverpoint ev.ip_frag;
    cp_mode     : coverpoint ev.mode;
    cp_ovf      : coverpoint ev.ovf_seen;
    cp_len      : coverpoint ev.frame_len {
      bins len_runt   = {[0:63]};
      bins len_small  = {[64:127]};
      bins len_med    = {[128:511]};
      bins len_large  = {[512:1517]};
      bins len_jumbo  = {[1518:$]};
    }

    // Cross-coverage: protocol × result × mode.
    x_kind_ip_ok      : cross cp_kind, cp_ip_ok;
    x_kind_l4_ok      : cross cp_kind, cp_l4_ok;
    x_kind_len        : cross cp_kind, cp_len;
    x_mode_ovf        : cross cp_mode, cp_ovf;
    x_frag_l4_ok      : cross cp_frag, cp_l4_ok;
    x_vlan_kind       : cross cp_vlan, cp_kind;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_frame = new();
  endfunction

  function void sample(cksum_event_t e);
    ev = e;
    cg_frame.sample();
  endfunction
endclass
