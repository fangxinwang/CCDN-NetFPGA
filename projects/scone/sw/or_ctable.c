
#include <stdlib.h>
#include <stdio.h>
#include <arpa/inet.h>
#include <string.h>
#include <assert.h>

#include "or_ctable.h"
#include "or_main.h"
#include "or_data_types.h"
#include "or_output.h"
#include "or_utils.h"
#include "or_netfpga.h"
#include "nf2/nf2util.h"
#include "reg_defines.h"



int get_nexthop_by_iface(router_state* rs, struct in_addr* nexthop, const char* interface)
{
    node* walker = rs->rtable;
    printf("get_nexthop_by_iface 1 ! \n");
    char nextip[20];
    while(walker){
        rtable_entry* re = (rtable_entry*)walker->data;
        printf("get_nexthop_by_iface 2 ! \n");
        if(strncmp(re->iface, interface, IF_LEN) == 0){
            printf("get_nexthop_by_iface 3 ! \n");
            nexthop->s_addr = re->ip.s_addr;

            inet_ntop(AF_INET, (void*)&(re->ip), nextip, 16 );
            printf("%s \n", nextip );
            printf("get_nexthop_by_iface 4 ! \n");
            return 1;
        }
        walker = walker->next;
    }
    return 0;
}

//first four parameters maintain the in_packet info, the last two paremeters store the lookup reslut by CtFw
// return value: 1 means hit, 0 means not hit
int get_nexthop_by_content(router_state* rs, struct in_addr* ct_name, uint16_t ct_vn, const char* interface,
                           struct in_addr* next_hop, char* nexthop_iface)
{
    //return 0;
    int hit_up_port[NUM_UPPORT+1] = {0};
    int hit_down_port[NUM_DNPORT+1] = {0};
    struct in_addr hit_up_ip[NUM_UPPORT+1];
    struct in_addr hit_down_ip[NUM_DNPORT+1];
    int hit_upcount=0, hit_downcount=0;

    int inport = getOneHotPortNumber(interface);
    int outport = 0;
    node* cur = NULL;
    node* next = NULL;
    ctable_entry* ce = NULL;
    int is_modified = 0;
    int chooseport = 0;


    cur = rs->ctable;
    while(cur){
        //printf(" come in \n");
        //printf("get_next_hop_by_content:front ctable length is %d\n", node_length(rs->ctable));
        next = cur->next;
        ce = (ctable_entry*)cur->data;
        if( ntohl(ct_name->s_addr) == ntohl(ce->content.s_addr) ){//judge if content match
            printf(" name equal, the request name is: %s \n",inet_ntoa(ce->content));
            if( ct_vn > ce->ver_num ){                        // judge if vn match
                printf(" vn: %d >>>>>>>>>> %d \n", ct_vn, ce->ver_num);
                printf("ctable remove \n");
                node_remove(&(rs->ctable), cur);
                //printf("middle ctable length is %d\n", node_length(rs->ctable));
                is_modified = 1;
            }
            else if( ct_vn == ce->ver_num ){
                printf(" vn: %d =========== %d \n", ct_vn, ce->ver_num);
                outport = getOneHotPortNumber(ce->iface);
                if( outport != inport ){ // judge if port not match
                    if(outport < DIVIDE_LINE){
                        hit_down_port[hit_downcount] = outport;
                        hit_down_ip[hit_downcount].s_addr = ce->nexthop.s_addr;
                        hit_downcount++;
                    }else{
                        hit_up_port[hit_upcount] = outport;
                        hit_up_ip[hit_upcount].s_addr = ce->nexthop.s_addr;
                        hit_upcount++;
                    }
                    if(hit_downcount > NUM_DNPORT || hit_upcount > NUM_UPPORT){
                        printf("Fatal error, there are too many matches in content FIB !!!!!!!!!!!! \n");
                        break;
                    }
                }
                else{
                    printf("ctable remove \n");
                    node_remove(&(rs->ctable), cur);
                    is_modified = 1;
                }
            }
            else{
                printf(" vn: %d <<<<<<<<<<<<< %d \n", ct_vn, ce->ver_num);
            }
        }
        cur = next;
        //printf("back ctable length is %d\n ", node_length(rs->ctable));
    }

    // if ctable is modified, then synchronize it to hardware
    if(is_modified){
        trigger_ctable_modified(rs);
        //printf("content table has been modified! \n");
    }

    //next step is multiport select, prefer to choose downward port with load balance(hash content name)
    chooseport = 0;
    if(hit_downcount + hit_upcount == 0) return 0;
    if( hit_downcount > 0 && hit_downcount<=NUM_DNPORT ){
        chooseport = ntohl(ct_name->s_addr)%hit_downcount;
        printf("chooseport = %d \n", chooseport);
        if( next_hop->s_addr ) printf("next_hop : %s \n", inet_ntoa(*next_hop));
        if( hit_down_ip[chooseport].s_addr ) printf("hit_down_ip[chooseport]: %s \n", inet_ntoa(hit_down_ip[chooseport]));
        next_hop->s_addr = hit_down_ip[chooseport].s_addr;
        getIfaceFromOneHotPortNumber(nexthop_iface, IF_LEN, hit_down_port[chooseport]);
        printf(" ### down phase \n");
        //printf(" ### hit_downcount = %d \n", hit_downcount);
        //printf(" ### nexthop_ip_addr dd = %d \n", next_hop->s_addr);
        //printf(" ### nexthop_ip_addr ss = %s \n", inet_ntoa(*next_hop));
        printf(" ### forward the REQUEST packet to DOWN port: %s \n", nexthop_iface);
        return 1;
    }
    if( hit_upcount > 0 && hit_upcount<=NUM_UPPORT ){
        chooseport = ntohl(ct_name->s_addr)%hit_upcount;
        printf("chooseport = %d \n", chooseport);
        next_hop->s_addr = hit_up_ip[chooseport].s_addr;
        getIfaceFromOneHotPortNumber(nexthop_iface, IF_LEN, hit_up_port[chooseport]);
        printf(" ### up phase \n");
        //printf(" ### hit_upcount = %d \n", hit_upcount);
        //printf(" ### nexthop_ip_addr = %d \n", next_hop->s_addr);
        //printf(" ### nexthop_ip_addr ss = %s \n", inet_ntoa(*next_hop));
        printf(" ### forward the REQUEST packet to UP port: %s \n", nexthop_iface);
        return 1;
    }

    return 0;
}


/*
 * NOT thread safe, lock the ctable before calling.
 * All parameters are copied out.
 * Returns: 0 if push back, 1 if update, 2 if insert back, -1 if failed to match
 */
int add_content(router_state* rs, struct in_addr* ct_name, uint16_t ver_num,
                struct in_addr* next_hop, const char* interface)
{

    int retval = -1;
	  ctable_entry* entry = (ctable_entry*)calloc(1, sizeof(ctable_entry));

		entry->content.s_addr = ct_name->s_addr;
		entry->ver_num = ver_num;
		entry->nexthop.s_addr = next_hop->s_addr;
		entry->is_active = 1;
		entry->is_static = 1;
		strncpy(entry->iface, interface, IF_LEN);


  	/* create a node, set data pointer to the new entry */
  	node* n = node_create();
  	n->data = entry;


  	uint32_t name = ntohl(ct_name->s_addr);
    uint16_t vn = ver_num;
    uint32_t nexthop = ntohl(next_hop->s_addr);


    node* walker = rs->ctable;
    int is_hit = 0;
    while( walker && (!is_hit) ){
        ctable_entry* ce = (ctable_entry*)walker->data;
        //name and iface are both equal
        if( ntohl(ce->content.s_addr)==name && strncmp(ce->iface, interface, IF_LEN)==0 ){
            is_hit = 1;
            node_update(&(rs->ctable), walker);
            retval = 1;
        }
        walker = walker->next;
    }
    int table_len = node_length(rs->ctable);
    if( is_hit==0 && table_len<=MAX_CTABLE_DEPTH ){
        printf("add content, content table_len = %d \n", table_len);
        if(table_len == 0){
            rs->ctable = n;
            retval = 0;
        }
        else if( table_len < MAX_CTABLE_DEPTH ){
            node_push_front(&(rs->ctable), n);
            retval = 0;
        }
        else{
            node_insert_front(&(rs->ctable), n);
            retval = 2;
        }
    }
    else if(is_hit == 0) {
        return -1;
    }


		/* write new ctable out to hardware */
		trigger_ctable_modified(rs);


  	return retval;
}

/* return n when there is n match, 0 if there is no match */
int del_content(router_state* rs, struct in_addr* ct_name, uint16_t ver_num, const char* interface)
{
    node *cur = NULL;
	node *next = NULL;
	ctable_entry* ce = NULL;
	int removed_contents = 0;

	cur = rs->ctable;
	while (cur) {
		next = cur->next;
		ce = (ctable_entry*)cur->data;
		if ( ntohl(ct_name->s_addr)==ntohl(ce->content.s_addr) && strncmp(ce->iface, interface, IF_LEN)==0 ) {
		    printf("ctable remove \n");
			node_remove(&(rs->ctable), cur);//node_remove has fault tolerance
			++removed_contents;
			printf("###  delete one content! \n");
		}

		cur = next;
	}

	/* write new rtable out to hardware */
	trigger_ctable_modified(rs);

	return removed_contents;
}


/*
 * NOT Threadsafe, ensure rtable locked for write
 */
void trigger_ctable_modified(router_state* rs) {

	if (rs->is_netfpga) {
		write_ctable_to_hw(rs);
	}
}



void write_ctable_to_hw(router_state* rs) {
	/* naively iterate through the 32 slots in hardware updating all entries */
	int i = 0;
	node* cur = rs->ctable;

	/* find first active entry before entering the loop, but why??? */
	//while (cur && !(((rtable_entry*)cur->data)->is_active)) {
	//	cur = cur->next;
	//}
    //printf("hw, ctable length is %d", node_length(rs->ctable));
	for (i = 0; i < ROUTER_OP_LUT_CCCP_TABLE_DEPTH; ++i) {

		if (cur) {
			ctable_entry* entry = (ctable_entry*)cur->data;
			/* write the content */
			writeReg(&(rs->netfpga), ROUTER_OP_LUT_CCCP_TABLE_ENTRY_NAME_REG, ntohl(entry->content.s_addr));
			/* write the version number */
			writeReg(&(rs->netfpga), ROUTER_OP_LUT_CCCP_TABLE_ENTRY_VN_REG, entry->ver_num);
			/* write the next hop */
			writeReg(&(rs->netfpga), ROUTER_OP_LUT_CCCP_TABLE_ENTRY_NEXT_HOP_IP_REG, ntohl(entry->nexthop.s_addr));
			/* write the port */
			writeReg(&(rs->netfpga), ROUTER_OP_LUT_CCCP_TABLE_ENTRY_OUTPUT_PORT_REG, getOneHotPortNumber(entry->iface));
			/* write the row number */
			writeReg(&(rs->netfpga), ROUTER_OP_LUT_CCCP_TABLE_WR_ADDR_REG, i);

			/* advance at least once */
			cur = cur->next;
			/* find the next active entry */
			//while (cur && !(((ctable_entry*)cur->data)->is_active)) {
			//	cur = cur->next;
			//}
		} else {
			/* write the content */
			writeReg(&(rs->netfpga), ROUTER_OP_LUT_CCCP_TABLE_ENTRY_NAME_REG, 0);
			/* write the next hop */
			writeReg(&(rs->netfpga), ROUTER_OP_LUT_CCCP_TABLE_ENTRY_NEXT_HOP_IP_REG, 0);
			/* write the port */
			writeReg(&(rs->netfpga), ROUTER_OP_LUT_CCCP_TABLE_ENTRY_OUTPUT_PORT_REG, 0);
			/* write the row number */
			writeReg(&(rs->netfpga), ROUTER_OP_LUT_CCCP_TABLE_WR_ADDR_REG, i);
		}
	}
}

// --- CCDN lock
void lock_ctable_rd(router_state *rs) {
	assert(rs);

	if(pthread_rwlock_rdlock(rs->ctable_lock) != 0) {
		perror("Failure getting ctable read lock");
	}
}

void lock_ctable_wr(router_state *rs) {
	assert(rs);

	if(pthread_rwlock_wrlock(rs->ctable_lock) != 0) {
		perror("Failure getting ctable write lock");
	}
}

void unlock_ctable(router_state *rs) {
	assert(rs);

	if(pthread_rwlock_unlock(rs->ctable_lock) != 0) {
		perror("Failure unlocking ctable lock");
	}
}
