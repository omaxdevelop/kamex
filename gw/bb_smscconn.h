/* Kamex — dynamic SMSC API shared types */

#ifndef BB_SMSCCONN_H
#define BB_SMSCCONN_H

#include "gwlib/gwlib.h"

typedef struct SmscDynamicRecord SmscDynamicRecord;

struct SmscDynamicRecord {
    Octstr *smsc_id;
    Octstr *host;
    long port;
    Octstr *system_id;
    Octstr *password;
    double throughput;
    Octstr *allowed_ip;
    int transceiver;
};

void smsc_dynamic_record_destroy(SmscDynamicRecord *r);
SmscDynamicRecord *smsc_dynamic_record_dup(SmscDynamicRecord *r);

Octstr *smsc2_api_json_smsc_list(void);

/* Create SMSC from API record; duplicates list entry into dynamic registry on success */
int smsc2_add_dynamic_smsc(SmscDynamicRecord *rec);

/* Like smsc2_remove_smsc plus removal from dynamic registry */
int smsc2_remove_smsc_api(Octstr *admin_id);

/*
 * PUT merged config: when no dynamic registry entry exists, only throughput is applied.
 * Otherwise reconnects if host/port/credentials/transceiver/allowed_ip changed.
 */
int smsc2_apply_smsc_put(Octstr *admin_id, SmscDynamicRecord *merged);

SmscDynamicRecord *smsc2_dynamic_record_get_copy(Octstr *admin_id);

#endif
