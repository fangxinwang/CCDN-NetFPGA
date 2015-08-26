#include <netinet/in.h>
#include <assert.h>
#include <string.h>
#include <stdlib.h>
#include <arpa/inet.h>

#include "or_main.h"
#include "or_iface.h"
#include "or_arp.h"
#include "or_icmp.h"
#include "or_rtable.h"
#include "or_output.h"
#include "or_utils.h"
#include "or_rtable.h"
#include "or_ip.h"
#include "or_pwospf.h"
#include "sr_lwtcp_glue.h"
#include "or_nat.h"
#include "or_data_types.h"
#include "or_cccp.h"
#include "or_ctable.h"


void process_cccp_packet(struct sr_instance* sr, const uint8_t * packet, unsigned int len, const char* interface)
{
    router_state *rs = get_router_state(sr);
    cccp_hdr *cccp = get_cccp_hdr(packet, len);
    ip_hdr *ip = get_ip_hdr(packet, len);
    uint16_t version_number = ntohs(cccp->cccp_vn);

    struct in_addr next_hop; //to store result by ip lookup
    char next_hop_iface[IF_LEN]; //to store result by ip lookup
    bzero(next_hop_iface, IF_LEN);

    struct in_addr* next_hop_ip_cccp = (struct in_addr*)calloc(1, sizeof(struct in_addr));// to store result by cccp
    next_hop_ip_cccp->s_addr = 1;
    char next_hop_iface_cccp[IF_LEN];
    bzero(next_hop_iface_cccp, IF_LEN);

    int retval_index_content = 0;

    //printf("Here is processing CCCP packet! \n");

    if(cccp->cccp_type == CCCP_TYPE_REQUEST){
        printf("scone has received a REQUEST packet! \n");

        //if content match
        retval_index_content = get_nexthop_by_content(rs, &(cccp->cccp_content), version_number,
                                   interface, next_hop_ip_cccp, next_hop_iface_cccp);
        if( retval_index_content ){
            //printf("index content FIB success!  \n");

            // modify dst ip
            printf("for REQUEST packet: before modify dst ip: %s \n",inet_ntoa(ip->ip_dst));
            printf("for REQUEST packet: before modify src ip: %s \n",inet_ntoa(ip->ip_src));
            ip->ip_dst.s_addr = next_hop_ip_cccp->s_addr;
            printf("for REQUEST packet: after  modify dst ip: %s \n",inet_ntoa(ip->ip_dst));
            printf("for REQUEST packet: after  modify src ip: %s \n",inet_ntoa(ip->ip_src));

        }// end of get_nexthop_by_content
        if(get_next_hop(&next_hop, next_hop_iface, IF_LEN, rs, &((get_ip_hdr(packet, len))->ip_dst)) == 0){// ip match
            /* check for outgoing interface is WAN */
            //printf("index location FIB success...  \n");
            iface_entry* iface = get_iface(rs, next_hop_iface);
            if(iface->is_wan) {

                lock_nat_table(rs);
                process_nat_int_packet(rs, packet, len, iface->ip);
                unlock_nat_table(rs);
            }

            //ip_hdr *ip = get_ip_hdr(packet, len);

            /* is ttl < 1? */
            if(ip->ip_ttl == 1) {

                /* send ICMP time exceeded */
                uint8_t icmp_type = ICMP_TYPE_TIME_EXCEEDED;
                uint8_t icmp_code = ICMP_CODE_TTL_EXCEEDED;
                send_icmp_packet(sr, packet, len, icmp_type, icmp_code);

            } else {
                /* decrement ttl */
                ip->ip_ttl--;

                /* recalculate checksum */
                bzero(&ip->ip_sum, sizeof(uint16_t));
                uint16_t checksum = htons(compute_ip_checksum(ip));
                ip->ip_sum = checksum;

                eth_hdr *eth = (eth_hdr *)packet;
                iface_entry* sr_if = get_iface(rs, next_hop_iface);
                assert(sr_if);

                /* update the eth header */
                populate_eth_hdr(eth, NULL, sr_if->addr, ETH_TYPE_IP);

                /* duplicate this packet here because the memory will be freed
                 * by send_ip, and our copy of the packet is only on loan
                 */

                uint8_t* packet_copy = (uint8_t*)malloc(len);
                memcpy(packet_copy, packet, len);

                /* forward packet out the next hop interface */
                send_ip(sr, packet_copy, len, &(next_hop), next_hop_iface);
            }

        }else{// no match
            printf("no match  \n");
            uint8_t icmp_type = ICMP_TYPE_DESTINATION_UNREACHABLE;
			uint8_t icmp_code = ICMP_CODE_NET_UNKNOWN;
			send_icmp_packet(sr, packet, len, icmp_type, icmp_code);

        }
    }
    else if(cccp->cccp_type == CCCP_TYPE_REPLY || cccp->cccp_type == CCCP_TYPE_FINISH){
        if(cccp->cccp_type == CCCP_TYPE_REPLY) printf("scone has received a REPLY packet! \n");
        else printf("scone has received a FINISH packet! \n");

        // for ip, get_next_hop ,return 1 means no match, 0 means there is a match
        if(get_next_hop(&next_hop, next_hop_iface, IF_LEN, rs, &((get_ip_hdr(packet, len))->ip_dst)) == 0){
            // for cccp, get the nexthop's ip address, by interface
            //printf(" the length of rtable is: %d", node_length(rs->rtable));
            //ip_hdr *ip = get_ip_hdr(packet, len);
            //in fact the next_hop_ip_cccp is actually the caching server's ip address
            next_hop_ip_cccp->s_addr = ip->ip_src.s_addr;

            //printf("scone has received a REPLY or FINISH packet 2 ! \n");
            if(strncmp(interface, "eth3", 4)){
            	int retval = add_content(rs, &(cccp->cccp_content), version_number, next_hop_ip_cccp, interface);
            	//printf("scone has received a REPLY or FINISH packet 3 ! \n");
            	switch(retval){
                	case 0: printf(" @@@@ add content, push back \n");break;
                	case 1: printf(" @@@@ add content, update \n");break;
                	case 2: printf(" @@@@ add content, insert back \n");break;
                	case -1:printf(" @@@@ failed to add content! \n");break;
                	default: printf(" @@@@ what the fuck, in or_cccp.c, process cccp packet, update content FAILED! \n");break;
            	}
            }



            /* check for outgoing interface is WAN */
				iface_entry* iface = get_iface(rs, next_hop_iface);
				if(iface->is_wan) {

					lock_nat_table(rs);
					process_nat_int_packet(rs, packet, len, iface->ip);
					unlock_nat_table(rs);
				}


				/* is ttl < 1? */
				if(ip->ip_ttl == 1) {

					/* send ICMP time exceeded */
					uint8_t icmp_type = ICMP_TYPE_TIME_EXCEEDED;
					uint8_t icmp_code = ICMP_CODE_TTL_EXCEEDED;
					send_icmp_packet(sr, packet, len, icmp_type, icmp_code);

				} else {
					/* decrement ttl */
					ip->ip_ttl--;

					/* recalculate checksum */
					bzero(&ip->ip_sum, sizeof(uint16_t));
					uint16_t checksum = htons(compute_ip_checksum(ip));
					ip->ip_sum = checksum;

					eth_hdr *eth = (eth_hdr *)packet;
					iface_entry* sr_if = get_iface(rs, next_hop_iface);
					assert(sr_if);

					/* update the eth header */
					populate_eth_hdr(eth, NULL, sr_if->addr, ETH_TYPE_IP);

					/* duplicate this packet here because the memory will be freed
				 	 * by send_ip, and our copy of the packet is only on loan
				 	 */

				 	uint8_t* packet_copy = (uint8_t*)malloc(len);
				 	memcpy(packet_copy, packet, len);

					/* forward packet out the next hop interface */
					send_ip(sr, packet_copy, len, &(next_hop), next_hop_iface);
				}

        } else{ // no match
            /**  to be continue */
            uint8_t icmp_type = ICMP_TYPE_DESTINATION_UNREACHABLE;
			uint8_t icmp_code = ICMP_CODE_NET_UNKNOWN;
			send_icmp_packet(sr, packet, len, icmp_type, icmp_code);
        }

    }
    else if(cccp->cccp_type == CCCP_TYPE_REJECT){
        printf("scone has received a REJECT packet! \n");
        // for ip, get_next_hop ,return 1 means no match, 0 means there is a match
        if(get_next_hop(&next_hop, next_hop_iface, IF_LEN, rs, &((get_ip_hdr(packet, len))->ip_dst)) == 0){
            // for cccp, get the nexthop's ip address, by interface

            int retval = del_content(rs, &(cccp->cccp_content), version_number, interface);
            printf("The REJECT packet has deleted %d content! \n", retval);

            /* check for outgoing interface is WAN */
				iface_entry* iface = get_iface(rs, next_hop_iface);
				if(iface->is_wan) {

					lock_nat_table(rs);
					process_nat_int_packet(rs, packet, len, iface->ip);
					unlock_nat_table(rs);
				}

				//ip_hdr *ip = get_ip_hdr(packet, len);

				/* is ttl < 1? */
				if(ip->ip_ttl == 1) {

					/* send ICMP time exceeded */
					uint8_t icmp_type = ICMP_TYPE_TIME_EXCEEDED;
					uint8_t icmp_code = ICMP_CODE_TTL_EXCEEDED;
					send_icmp_packet(sr, packet, len, icmp_type, icmp_code);

				} else {
					/* decrement ttl */
					ip->ip_ttl--;

					/* recalculate checksum */
					bzero(&ip->ip_sum, sizeof(uint16_t));
					uint16_t checksum = htons(compute_ip_checksum(ip));
					ip->ip_sum = checksum;

					eth_hdr *eth = (eth_hdr *)packet;
					iface_entry* sr_if = get_iface(rs, next_hop_iface);
					assert(sr_if);

					/* update the eth header */
					populate_eth_hdr(eth, NULL, sr_if->addr, ETH_TYPE_IP);

					/* duplicate this packet here because the memory will be freed
				 	 * by send_ip, and our copy of the packet is only on loan
				 	 */

				 	uint8_t* packet_copy = (uint8_t*)malloc(len);
				 	memcpy(packet_copy, packet, len);

					/* forward packet out the next hop interface */
					send_ip(sr, packet_copy, len, &(next_hop), next_hop_iface);
				}

        } else{ // no match
            /**  to be continue */
            uint8_t icmp_type = ICMP_TYPE_DESTINATION_UNREACHABLE;
			uint8_t icmp_code = ICMP_CODE_NET_UNKNOWN;
			send_icmp_packet(sr, packet, len, icmp_type, icmp_code);
        }


    }
    else{
        printf("This kind of CCCP packet is not existing, will forward it by IP\n");

        if(get_next_hop(&next_hop, next_hop_iface, IF_LEN, rs, &((get_ip_hdr(packet, len))->ip_dst)) == 0){

            /* check for outgoing interface is WAN */
				iface_entry* iface = get_iface(rs, next_hop_iface);
				if(iface->is_wan) {

					lock_nat_table(rs);
					process_nat_int_packet(rs, packet, len, iface->ip);
					unlock_nat_table(rs);
				}

				//ip_hdr *ip = get_ip_hdr(packet, len);

				/* is ttl < 1? */
				if(ip->ip_ttl == 1) {

					/* send ICMP time exceeded */
					uint8_t icmp_type = ICMP_TYPE_TIME_EXCEEDED;
					uint8_t icmp_code = ICMP_CODE_TTL_EXCEEDED;
					send_icmp_packet(sr, packet, len, icmp_type, icmp_code);

				} else {
					/* decrement ttl */
					ip->ip_ttl--;

					/* recalculate checksum */
					bzero(&ip->ip_sum, sizeof(uint16_t));
					uint16_t checksum = htons(compute_ip_checksum(ip));
					ip->ip_sum = checksum;

					eth_hdr *eth = (eth_hdr *)packet;
					iface_entry* sr_if = get_iface(rs, next_hop_iface);
					assert(sr_if);

					/* update the eth header */
					populate_eth_hdr(eth, NULL, sr_if->addr, ETH_TYPE_IP);

					/* duplicate this packet here because the memory will be freed
				 	 * by send_ip, and our copy of the packet is only on loan
				 	 */

				 	uint8_t* packet_copy = (uint8_t*)malloc(len);
				 	memcpy(packet_copy, packet, len);

					/* forward packet out the next hop interface */
					send_ip(sr, packet_copy, len, &(next_hop), next_hop_iface);
				}

        } else{ // no match
            /**  to be continue */
            uint8_t icmp_type = ICMP_TYPE_DESTINATION_UNREACHABLE;
			uint8_t icmp_code = ICMP_CODE_NET_UNKNOWN;
			send_icmp_packet(sr, packet, len, icmp_type, icmp_code);
        }
    }//end of not cccp packet

}// end of process cccp packet

/*
 * Takes raw packet pointer and length, returns pointer to ip segment
 */
cccp_hdr* get_cccp_hdr(const uint8_t* packet, unsigned int len) {
	return (cccp_hdr*)(packet + ETH_HDR_LEN + IP_HDR_LEN);
}




