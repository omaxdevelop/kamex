/*
 * REST API /api/smsc — dynamic SMSC management (JSON + X-Admin-Token).
 */

#include "gw-config.h"

#include <signal.h>
#include <string.h>

#include "gwlib/gwlib.h"
#include "gwlib/http.h"
#include "gwlib/cJSON.h"

#include "bearerbox.h"
#include "bb_smscconn.h"
#include "bb_smsc_api.h"

extern volatile sig_atomic_t bb_status;

static void api_reply_json(HTTPClient *client, int http_status, Octstr *json_body)
{
    List *hdrs;

    hdrs = gwlist_create();
    http_header_add(hdrs, "Content-Type", "application/json");
    http_send_reply(client, http_status, hdrs, json_body);
    octstr_destroy(json_body);
    http_destroy_headers(hdrs);
}

static Octstr *json_err(const char *msg)
{
    return octstr_format("{\"error\":\"%s\"}", msg);
}

static int api_token_ok(List *headers, Octstr *api_token)
{
    Octstr *hdr;
    int ok;

    if (api_token == NULL || octstr_len(api_token) == 0)
        return 0;
    hdr = http_header_value(headers, octstr_imm("X-Admin-Token"));
    if (hdr == NULL)
        return 0;
    ok = octstr_compare(hdr, api_token) == 0;
    octstr_destroy(hdr);
    return ok;
}

static SmscDynamicRecord *parse_smsc_record_json(cJSON *root, int require_all, Octstr **err)
{
    cJSON *j;
    SmscDynamicRecord *rec;

    *err = NULL;
    rec = gw_malloc(sizeof(*rec));
    memset(rec, 0, sizeof(*rec));

    j = cJSON_GetObjectItem(root, "smsc_id");
    if (!j || !cJSON_IsString(j) || j->valuestring == NULL) {
        if (require_all) {
            *err = octstr_create("smsc_id required");
            goto fail;
        }
        rec->smsc_id = NULL;
    } else {
        rec->smsc_id = octstr_create(j->valuestring);
        octstr_strip_blanks(rec->smsc_id);
    }

    j = cJSON_GetObjectItem(root, "system_id");
    if (!j || !cJSON_IsString(j) || j->valuestring == NULL) {
        if (require_all) {
            *err = octstr_create("system_id required");
            goto fail;
        }
        rec->system_id = NULL;
    } else {
        rec->system_id = octstr_create(j->valuestring);
        octstr_strip_blanks(rec->system_id);
        if (octstr_len(rec->system_id) > 16) {
            *err = octstr_create("system_id exceeds 16 characters");
            goto fail;
        }
    }

    j = cJSON_GetObjectItem(root, "password");
    if (!j || !cJSON_IsString(j) || j->valuestring == NULL) {
        if (require_all) {
            *err = octstr_create("password required");
            goto fail;
        }
        rec->password = NULL;
    } else {
        rec->password = octstr_create(j->valuestring);
        if (octstr_len(rec->password) > 16) {
            *err = octstr_create("password exceeds 16 characters");
            goto fail;
        }
    }

    j = cJSON_GetObjectItem(root, "host");
    if (j && cJSON_IsString(j) && j->valuestring != NULL && strlen(j->valuestring) > 0)
        rec->host = octstr_create(j->valuestring);
    else
        rec->host = octstr_create("127.0.0.1");

    rec->port = 2775;
    j = cJSON_GetObjectItem(root, "port");
    if (j && cJSON_IsNumber(j))
        rec->port = (long) j->valuedouble;

    rec->throughput = 10.0;
    j = cJSON_GetObjectItem(root, "tps");
    if (j && cJSON_IsNumber(j))
        rec->throughput = j->valuedouble;

    j = cJSON_GetObjectItem(root, "allowed_ip");
    if (j && cJSON_IsString(j) && j->valuestring != NULL && strlen(j->valuestring) > 0)
        rec->allowed_ip = octstr_create(j->valuestring);
    else
        rec->allowed_ip = NULL;

    rec->transceiver = 1;
    j = cJSON_GetObjectItem(root, "transceiver");
    if (j && (cJSON_IsBool(j) || cJSON_IsNumber(j))) {
        if (cJSON_IsBool(j))
            rec->transceiver = cJSON_IsTrue(j) ? 1 : 0;
        else
            rec->transceiver = j->valuedouble != 0.0 ? 1 : 0;
    }

    return rec;

fail:
    smsc_dynamic_record_destroy(rec);
    return NULL;
}

static void merge_put_json(SmscDynamicRecord *base, cJSON *root)
{
    cJSON *j;

    j = cJSON_GetObjectItem(root, "tps");
    if (j && cJSON_IsNumber(j))
        base->throughput = j->valuedouble;

    j = cJSON_GetObjectItem(root, "allowed_ip");
    if (j) {
        octstr_destroy(base->allowed_ip);
        base->allowed_ip = NULL;
        if (cJSON_IsString(j) && j->valuestring != NULL && strlen(j->valuestring) > 0)
            base->allowed_ip = octstr_create(j->valuestring);
    }

    j = cJSON_GetObjectItem(root, "host");
    if (j && cJSON_IsString(j) && j->valuestring != NULL && strlen(j->valuestring) > 0) {
        octstr_destroy(base->host);
        base->host = octstr_create(j->valuestring);
    }

    j = cJSON_GetObjectItem(root, "port");
    if (j && cJSON_IsNumber(j))
        base->port = (long) j->valuedouble;

    j = cJSON_GetObjectItem(root, "system_id");
    if (j && cJSON_IsString(j) && j->valuestring != NULL) {
        octstr_destroy(base->system_id);
        base->system_id = octstr_create(j->valuestring);
        octstr_strip_blanks(base->system_id);
    }

    j = cJSON_GetObjectItem(root, "password");
    if (j && cJSON_IsString(j) && j->valuestring != NULL) {
        octstr_destroy(base->password);
        base->password = octstr_create(j->valuestring);
    }

    j = cJSON_GetObjectItem(root, "transceiver");
    if (j && (cJSON_IsBool(j) || cJSON_IsNumber(j))) {
        if (cJSON_IsBool(j))
            base->transceiver = cJSON_IsTrue(j) ? 1 : 0;
        else
            base->transceiver = j->valuedouble != 0.0 ? 1 : 0;
    }
}

void bb_smsc_api_dispatch(HTTPClient *client, Octstr *url, List *headers, Octstr *body,
                          Octstr *ourl, List *cgivars, Octstr *api_token)
{
    int method;
    Octstr *reply;
    Octstr *rest_id;
    long url_len;

    if (!api_token_ok(headers, api_token)) {
        reply = json_err("Forbidden");
        api_reply_json(client, HTTP_FORBIDDEN, reply);
        goto cleanup;
    }

    if (bb_status == BB_SHUTDOWN || bb_status == BB_DEAD) {
        reply = json_err("Gateway shutting down");
        api_reply_json(client, HTTP_SERVICE_UNAVAILABLE, reply);
        goto cleanup;
    }

    url_len = octstr_len(url);
    rest_id = NULL;
    if (url_len > 9 && octstr_get_char(url, 8) == '/')
        rest_id = octstr_copy(url, 9, url_len - 9);

    if (rest_id != NULL)
        octstr_url_decode(rest_id);

    method = http_method(client);

    /* Collection: api/smsc */
    if (rest_id == NULL || octstr_len(rest_id) == 0) {
        if (method == HTTP_METHOD_GET) {
            reply = smsc2_api_json_smsc_list();
            api_reply_json(client, HTTP_OK, reply);
            goto cleanup;
        }
        if (method == HTTP_METHOD_POST) {
            cJSON *root;
            SmscDynamicRecord *rec;
            Octstr *err;
            List *rh;

            if (body == NULL || octstr_len(body) == 0) {
                reply = json_err("Empty body");
                api_reply_json(client, HTTP_BAD_REQUEST, reply);
                goto cleanup;
            }
            root = cJSON_Parse(octstr_get_cstr(body));
            if (root == NULL) {
                reply = json_err("Invalid JSON");
                api_reply_json(client, HTTP_BAD_REQUEST, reply);
                goto cleanup;
            }
            rec = parse_smsc_record_json(root, 1, &err);
            cJSON_Delete(root);
            if (rec == NULL) {
                reply = json_err(octstr_get_cstr(err));
                octstr_destroy(err);
                api_reply_json(client, HTTP_BAD_REQUEST, reply);
                goto cleanup;
            }

            if (rec->smsc_id == NULL || octstr_len(rec->smsc_id) == 0) {
                reply = json_err("smsc_id required");
                smsc_dynamic_record_destroy(rec);
                api_reply_json(client, HTTP_BAD_REQUEST, reply);
                goto cleanup;
            }

            switch (smsc2_add_dynamic_smsc(rec)) {
                case 0: {
                    Octstr *loc_path;

                    reply = octstr_create("{\"ok\":true}");
                    rh = gwlist_create();
                    http_header_add(rh, "Content-Type", "application/json");
                    loc_path = octstr_format("/api/smsc/%S", rec->smsc_id);
                    http_header_add(rh, "Location", octstr_get_cstr(loc_path));
                    octstr_destroy(loc_path);
                    http_send_reply(client, HTTP_CREATED, rh, reply);
                    octstr_destroy(reply);
                    http_destroy_headers(rh);
                    smsc_dynamic_record_destroy(rec);
                    octstr_destroy(rest_id);
                    octstr_destroy(url);
                    octstr_destroy(ourl);
                    octstr_destroy(body);
                    http_destroy_cgiargs(cgivars);
                    http_destroy_headers(headers);
                    return;
                }
                case -2:
                    reply = json_err("smsc_id already exists");
                    smsc_dynamic_record_destroy(rec);
                    api_reply_json(client, HTTP_BAD_REQUEST, reply);
                    goto cleanup;
                default:
                    reply = json_err("Could not create SMSC connection");
                    smsc_dynamic_record_destroy(rec);
                    api_reply_json(client, HTTP_BAD_REQUEST, reply);
                    goto cleanup;
            }
        }
        reply = json_err("Method not allowed");
        api_reply_json(client, HTTP_BAD_METHOD, reply);
        goto cleanup;
    }

    /* Resource: api/smsc/{id} */
    if (method == HTTP_METHOD_DELETE) {
        if (smsc2_remove_smsc_api(rest_id) == 0) {
            reply = octstr_create("{\"ok\":true}");
            api_reply_json(client, HTTP_OK, reply);
        } else {
            reply = json_err("SMSC not found");
            api_reply_json(client, HTTP_NOT_FOUND, reply);
        }
        goto cleanup;
    }

    if (method == HTTP_METHOD_PUT) {
        cJSON *root;
        SmscDynamicRecord *merged;
        SmscDynamicRecord *dyn;

        if (body == NULL || octstr_len(body) == 0) {
            reply = json_err("Empty body");
            api_reply_json(client, HTTP_BAD_REQUEST, reply);
            goto cleanup;
        }
        root = cJSON_Parse(octstr_get_cstr(body));
        if (root == NULL) {
            reply = json_err("Invalid JSON");
            api_reply_json(client, HTTP_BAD_REQUEST, reply);
            goto cleanup;
        }

        dyn = smsc2_dynamic_record_get_copy(rest_id);
        if (dyn != NULL) {
            merge_put_json(dyn, root);
            merged = dyn;
        } else {
            merged = gw_malloc(sizeof(*merged));
            memset(merged, 0, sizeof(*merged));
            merged->smsc_id = octstr_duplicate(rest_id);
            merged->host = octstr_create("127.0.0.1");
            merged->port = 2775;
            merged->system_id = octstr_create("");
            merged->password = octstr_create("");
            merged->throughput = 10.0;
            merged->allowed_ip = NULL;
            merged->transceiver = 1;
            merge_put_json(merged, root);
        }
        cJSON_Delete(root);

        switch (smsc2_apply_smsc_put(rest_id, merged)) {
            case 0:
                smsc_dynamic_record_destroy(merged);
                reply = octstr_create("{\"ok\":true}");
                api_reply_json(client, HTTP_OK, reply);
                goto cleanup;
            case -1:
                smsc_dynamic_record_destroy(merged);
                reply = json_err("SMSC not found");
                api_reply_json(client, HTTP_NOT_FOUND, reply);
                goto cleanup;
            default:
                smsc_dynamic_record_destroy(merged);
                reply = json_err("Update failed");
                api_reply_json(client, HTTP_BAD_REQUEST, reply);
                goto cleanup;
        }
    }

    reply = json_err("Method not allowed");
    api_reply_json(client, HTTP_BAD_METHOD, reply);

cleanup:
    octstr_destroy(rest_id);
    octstr_destroy(url);
    octstr_destroy(ourl);
    octstr_destroy(body);
    http_destroy_cgiargs(cgivars);
    http_destroy_headers(headers);
}
