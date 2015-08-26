#include "or_data_types.h"
#include "sr_base_internal.h"

void process_cccp_packet(struct sr_instance* sr, const uint8_t * packet, unsigned int len, const char* interface);

cccp_hdr* get_cccp_hdr(const uint8_t* packet, unsigned int len);



