# Changelog

All notable changes to Kamex (formerly Kannel) will be documented in this file.

## [Unreleased]

### Fixed
- Declare `admin-api-token` in `gwlib/cfg.def` for `group = core` so bearerbox no longer panics at startup (`cfg_get` rejected an unknown variable).

## [1.8.1] - 2026-01-18

### Added
- **Dynamic SMSC REST API** — `GET|POST /api/smsc`, `PUT|DELETE /api/smsc/{id}` on the admin HTTP port with JSON bodies and `X-Admin-Token` (config `admin-api-token` in `group = core`). SMSCs added via `POST` are built from an in-memory `CfgGroup` (no config reload); omitted `host` defaults to `127.0.0.1`. Implementation uses bundled **cJSON** in `gwlib/`.
- **Prometheus /metrics endpoint** - Native Prometheus monitoring support
  - Counters: `kamex_sms_sent_total`, `kamex_sms_received_total`, `kamex_dlr_*_total`
  - Gauges: `kamex_uptime_seconds`, `kamex_smsc_online`, `kamex_sms_queue_*`
  - Rates: `kamex_sms_sent_rate`, `kamex_sms_received_rate` (per second)
  - Log queue metrics: `kamex_log_queue_depth`, `kamex_log_dropped_total`
  - No authentication required (standard for metrics endpoints)
- **OpenAPI specification** - Complete API documentation in `doc/openapi.yaml`
  - Admin API endpoints (monitoring, control, SMSC management)
  - SMS API endpoints (sendsms with all parameters)
  - Compatible with Swagger UI and code generators
- **Reproducible builds** - Enterprise-grade build verification and compliance
  - Supports `SOURCE_DATE_EPOCH` for deterministic timestamps
  - `--enable-reproducible` configure flag (auto-enabled with SOURCE_DATE_EPOCH)
  - Strips absolute paths from binaries with `-ffile-prefix-map`
  - Identical SHA256 hashes for same source + environment
  - Docker images: pinned base image digest and EPEL version
  - GitHub Actions CI sets `SOURCE_DATE_EPOCH` automatically
  - Addons (SQLBox, OpenSMPPBox) support reproducible builds
- **Config validation** - Validate configuration files without starting services (nginx-style)
  - `bearerbox -t /etc/kamex/kamex.conf` - test bearerbox config
  - `smsbox -t /etc/kamex/kamex.conf` - test smsbox config
  - Clean output: `bearerbox: configuration file ... test is successful`
  - Returns exit code 0 on success, 1 on failure
  - Useful for CI/CD pipelines and deployment automation
- **Command-line help** - `bearerbox --help` and `smsbox --help` now work
  - Full usage information with all options
  - Examples for common operations
  - See `doc/cli.md` for complete documentation
- **Structured JSON logging** - Machine-readable log format for log aggregation
  - Enable with `log-format = json` in core or smsbox groups
  - Output: `{"ts":"...","level":"info","pid":123,"tid":0,"msg":"..."}`
  - Compatible with ELK, Loki, Splunk, Fluentd, and other log systems
  - See `doc/logging.md` for examples with jq
- **Environment variable expansion** - Reference env vars in config with `${VAR}` syntax
  - `admin-password = ${ADMIN_PASSWORD}` expands from environment
  - Mixed content supported: `host = smsc.${ENV}.example.com`
  - Enables Docker/K8s secrets injection without config changes
  - See `doc/configuration.md` for usage examples
- **SBOM** - CycloneDX 1.7 Software Bill of Materials (`sbom.json`)
  - Runtime dependencies with exact versions from UBI 10
  - Package URLs (PURLs) for vulnerability scanning
  - For security compliance and supply chain verification

## [1.8.0] - 2026-01-12

### Added
- **Async logging** - Log messages are now queued and written by a dedicated writer thread
  - Bounded queue (128K entries, ~512MB max) prevents unbounded growth
  - Calling threads no longer block on I/O - ~10x throughput improvement
  - PANIC level remains synchronous (crash context must hit disk immediately)
  - Per-SMSC exclusive logging preserved via `exclusive_idx` routing
  - 4KB buffer per entry handles 9-segment SMS in hex logs
- **Logging observability** - New monitoring endpoints for log queue health
  - `/health` returns `warn` status when queue >= 80% or messages dropped
  - `/status.json` includes `logging` section with queue depth, dropped count, writer status
- **Architecture documentation** - `doc/logging.md` explains async logging design
- **RPM logrotate** - Logrotate config now included in RPM package

### Fixed
- **Async logging security** - Fixed multiple issues found during security audit:
  - Race condition: capture `log_queue` to local variable before use
  - Memory leak: use `gw_native_free` destructor in `gwlist_destroy`
  - Out-of-bounds: validate `exclusive_idx < num_logfiles` before array access
  - Shutdown race: set `log_queue = NULL` before destroying queue
- **fakesmsc installation** - Now installs real binary instead of libtool wrapper
- **test_headers.c** - Removed WAP/WSP dependencies, now tests HTTP headers only
- **check_sendsms.sh** - Fixed incorrect path and cumulative auth failure count
- **check_headers.sh** - Updated for simplified test_headers
- **run-checks** - Now checks exit codes instead of treating any stderr as failure

### Changed
- Log writer thread uses `gwthread_create()` for proper gwlib integration
- `LogQueueStatus` struct added to `gwlib/log.h` for queue monitoring
- Queue size reduced from 512K to 128K entries (still handles sustained bursts)

## [1.7.8] - 2026-01-12

### Added
- **OpenSMPPBox packaging** - RPM package for kamex-opensmppbox addon
- **OpenSMPPBox systemd service** - `kamex-opensmppbox.service` with security hardening

### Changed
- Modernized OpenSMPPBox configure.ac, removed DocBook build system
- GitHub workflow now builds all 3 packages: kamex, kamex-sqlbox, kamex-opensmppbox

## [1.7.7] - 2026-01-12

### Removed
- **SQLite2 support** - Removed obsolete SQLite 2.x database backend (use SQLite3)
- **libsdb support** - Removed dead libsdb database abstraction library
- Removed ~500 lines of dead code from gwlib, gw, and sqlbox

### Changed
- Cleaned up database pool enum and initialization code
- Updated test_dbpool.c to remove SQLite2 tests

## [1.7.6] - 2026-01-12

### Added
- **SQLBox packaging** - RPM package for kamex-sqlbox addon
- **SQLBox systemd service** - `kamex-sqlbox.service` with security hardening

### Changed
- **Systemd services** - Use `RuntimeDirectory`, `StateDirectory`, `LogsDirectory` for better compatibility
- **Systemd paths** - Service files now use `@SBINDIR@` template for correct paths in both `make install` and RPM

### Fixed
- **Namespace errors** - Fixed `status=226/NAMESPACE` errors in containers/VMs
- **SQLBox build** - Modernized configure.ac, removed DocBook build system

## [1.7.5] - 2026-01-10

### Rebrand
- **Renamed from Kannel to Kamex** due to licensing restrictions
- New MIT license for Kamex code, original Kannel code remains under Kannel Software License 1.0
- Configuration files remain compatible with Kannel
- Systemd service files renamed to `kamex-bearerbox`, `kamex-smsbox`
- Paths changed to `/etc/kamex`, `/var/log/kamex`, etc.

### Added
- **Web Admin Panel** - Built-in dashboard at `/` and `/admin` with real-time monitoring
  - Dashboard with SMS/DLR traffic stats and SMSC status
  - Queue viewer showing pending messages from store-status
  - Send SMS form for testing
  - Gateway controls (suspend/resume/shutdown/restart SMSCs)
  - Auto-refresh toggle (5s/15s/30s/Off)
  - Admin mode vs view-only mode detection
- **JSON API** - Modern REST-like endpoints
  - `/api/sendsms` - POST-only JSON endpoint for sending SMS
  - `/status.json` - JSON status output with rates and SMSC details
  - Token authentication via `X-API-Key` header and `api-token` config
- **Health Check** - `/health` endpoint for load balancers and Kubernetes
- CORS headers for smsbox sendsms endpoint

### Removed
- **libxml2 dependency** - No longer required
- **WAP/WML support** - Removed all WAP-related code and files
- **RADIUS support** - Removed RADIUS authentication
- Legacy platform support (Solaris, Interix3, FreeBSD c_r)
- SVN/CVS artifacts and dead code

### Changed
- Admin panel HTML embedded in binary (no external file needed)
- OpenSSL 1.1+ thread safety test skipped (always thread-safe)
- Modernized autoconf configuration

### Fixed
- JSON SMSC status comma handling for multiple SMSCs
- OpenSSL auto-detection for modern distros
- iconv library detection for Linux systems

## [1.6.5] - 2025-12-01

### Added
- Unix socket support for Redis connections
- Systemd service files with security hardening
- Logrotate configuration
- Performance benchmarks
- GitHub-friendly README.md and markdown documentation

### Changed
- Updated build dependencies for Fedora/EL10
- Replaced bootstrap.sh with standard autoreconf

### Fixed
- OpenSSL detection for modern distros
- gettext m4 macros
- Benchmark scripts

## [1.6.4] and earlier

See the original Kannel changelog for historical changes.

## Part 1 Dynamic SMSC API — functions added or modified

| Function | File | Description |
|----------|------|-------------|
| `cfg_group_create` | gwlib/cfg.c | Allocates an ephemeral `CfgGroup` for `cfg_set`-based SMSC definitions |
| `cfg_group_destroy` | gwlib/cfg.c | Frees an ephemeral `CfgGroup` |
| `octstr_cmp_null_safe` (static) | gw/bb_smscconn.c | Compares optional `Octstr` fields for dynamic SMSC diff |
| `smsc2_cfg_group_from_record` (static) | gw/bb_smscconn.c | Maps `SmscDynamicRecord` to SMPP `CfgGroup` keys |
| `dynamic_record_need_reconnect` (static) | gw/bb_smscconn.c | Decides if PUT requires reconnect vs throughput-only update |
| `smsc_dynamic_record_dup` | gw/bb_smscconn.c | Deep-copies a dynamic SMSC record |
| `smsc_dynamic_record_destroy` | gw/bb_smscconn.c | Frees a dynamic SMSC record |
| `smsc2_api_json_smsc_list` | gw/bb_smscconn.c | Builds JSON array of SMSCs for `GET /api/smsc` |
| `smsc2_add_dynamic_smsc` | gw/bb_smscconn.c | Appends an API-defined SMSC without reloading the config file |
| `smsc2_dynamic_record_get_copy` | gw/bb_smscconn.c | Returns a copy of the stored record for API-managed SMSCs |
| `smsc2_apply_smsc_put` | gw/bb_smscconn.c | Applies `PUT` (throughput and/or reconnect from merged record) |
| `smsc2_remove_smsc_api` | gw/bb_smscconn.c | Removes SMSC and drops stored dynamic record |
| `api_reply_json` (static) | gw/bb_smsc_api.c | Sends JSON HTTP responses |
| `json_err` (static) | gw/bb_smsc_api.c | Builds minimal JSON error body |
| `api_token_ok` (static) | gw/bb_smsc_api.c | Validates `X-Admin-Token` against configured token |
| `parse_smsc_record_json` (static) | gw/bb_smsc_api.c | Parses POST body into `SmscDynamicRecord` |
| `merge_put_json` (static) | gw/bb_smsc_api.c | Merges PUT JSON into a dynamic record |
| `bb_smsc_api_dispatch` | gw/bb_smsc_api.c | Routes `/api/smsc` HTTP methods and status codes |
| `httpd_serve` | gw/bb_http.c | Dispatches `api/smsc` before legacy admin commands |
| `httpadmin_start` | gw/bb_http.c | Loads `admin-api-token` into `ha_api_token` |
| `httpadmin_stop` | gw/bb_http.c | Destroys `ha_api_token` |
