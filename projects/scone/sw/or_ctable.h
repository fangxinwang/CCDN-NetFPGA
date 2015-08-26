#include "or_data_types.h"
#include "sr_base_internal.h"

#define NUM_UPPORT 1
#define NUM_DNPORT 3
#define DIVIDE_LINE 20


int get_nexthop_by_iface(router_state* rs, struct in_addr* nexthop, const char* interface);

int get_nexthop_by_content(router_state* rs, struct in_addr* ct_name, uint16_t ct_vn, const char* interface, struct in_addr* next_hop, char* nexthop_iface);
int add_content(router_state* rs, struct in_addr* ct_name, uint16_t ver_num, struct in_addr* next_hop, const char* interface);

int del_content(router_state* rs, struct in_addr* ct_name, uint16_t ver_num, const char* interface);
void trigger_ctable_modified(router_state* rs);
void write_ctable_to_hw(router_state* rs);

// --- CCDN lock
void lock_ctable_rd(router_state *rs);
void lock_ctable_wr(router_state *rs);
void unlock_ctable(router_state *rs);
