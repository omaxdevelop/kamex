#ifndef BB_SMSC_API_H
#define BB_SMSC_API_H

#include "gwlib/gwlib.h"
#include "gwlib/http.h"

void bb_smsc_api_dispatch(HTTPClient *client, Octstr *url, List *headers, Octstr *body,
                          Octstr *ourl, List *cgivars, Octstr *api_token);

#endif
