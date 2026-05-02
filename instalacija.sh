#!/usr/bin/env bash
#===============================================================================
# Skripta za instalaciju Kamex SMS Gateway na Ubuntu 22.04 LTS
# Mora se pokrenuti kao root korisnik (sudo su ili direktno root login)
#===============================================================================

set -euo pipefail

# --- Definicije boja ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# --- Konfiguracija ---
readonly REPO_URL="https://github.com/omaxdevelop/kamex.git"
readonly INSTALL_DIR="/opt/kamex"
readonly CONFIG_DIR="/etc/kamex"
readonly CONFIG_FILE="${CONFIG_DIR}/kamex.conf"

# --- Pomoćne funkcije ---
log_success() { echo -e "${GREEN}[USPEH]${NC} $*"; }
log_error()   { echo -e "${RED}[GREŠKA]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[UPOZORENJE]${NC} $*"; }
log_info()    { echo -e "${CYAN}[INFO]${NC} $*"; }

# Provera da li je skripta pokrenuta kao root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Ova skripta mora biti pokrenuta kao root korisnik."
        log_info "Prijavite se kao root (ili koristite 'sudo su') i pokrenite je ponovo."
        exit 1
    fi
    log_success "Root privilegije potvrđene."
}

# Instalacija osnovnih alata (dodat gettext)
install_basic_tools() {
    log_info "Ažuriranje liste paketa..."
    apt-get update -qq

    log_info "Instaliranje osnovnih alata za build (uključujući gettext)..."
    apt-get install -y -qq build-essential autotools-dev autoconf automake libtool \
                          pkg-config git curl wget gettext
    log_success "Osnovni alati su instalirani."
}

# Instalacija obaveznih i opcionih zavisnosti
install_dependencies() {
    log_info "Instaliranje obaveznih razvojnih biblioteka..."
    apt-get install -y -qq libssl-dev
    log_success "Obavezne biblioteke su instalirane."

    echo ""
    log_warning "Slede opcione zavisnosti za baze podataka."
    echo "   Ako vam određena baza nije potrebna, slobodno odgovorite sa 'n'."
    echo ""

    # MySQL/MariaDB
    read -p "   Želite MySQL/MariaDB podršku? (y/n) [y]: " mysql_choice
    mysql_choice=${mysql_choice:-y}
    if [[ "$mysql_choice" =~ ^[Yy]$ ]]; then
        apt-get install -y -qq libmysqlclient-dev
        log_success "MySQL/MariaDB biblioteka je instalirana."
    else
        log_info "MySQL/MariaDB podrška je preskočena."
    fi

    # PostgreSQL
    read -p "   Želite PostgreSQL podršku? (y/n) [y]: " pgsql_choice
    pgsql_choice=${pgsql_choice:-y}
    if [[ "$pgsql_choice" =~ ^[Yy]$ ]]; then
        apt-get install -y -qq libpq-dev
        log_success "PostgreSQL biblioteka je instalirana."
    else
        log_info "PostgreSQL podrška je preskočena."
    fi

    # SQLite3
    read -p "   Želite SQLite3 podršku? (y/n) [y]: " sqlite_choice
    sqlite_choice=${sqlite_choice:-y}
    if [[ "$sqlite_choice" =~ ^[Yy]$ ]]; then
        apt-get install -y -qq libsqlite3-dev
        log_success "SQLite3 biblioteka je instalirana."
    else
        log_info "SQLite3 podrška je preskočena."
    fi

    # Redis
    read -p "   Želite Redis (hiredis) podršku? (y/n) [y]: " redis_choice
    redis_choice=${redis_choice:-y}
    if [[ "$redis_choice" =~ ^[Yy]$ ]]; then
        apt-get install -y -qq libhiredis-dev
        log_success "Redis biblioteka je instalirana."
    else
        log_info "Redis podrška je preskočena."
    fi

    # Cassandra
    read -p "   Želite Cassandra podršku? (y/n) [n]: " cassandra_choice
    cassandra_choice=${cassandra_choice:-n}
    if [[ "$cassandra_choice" =~ ^[Yy]$ ]]; then
        log_warning "Cassandra podrška nije u Ubuntu repo. Instalirajte ručno CPP driver."
    fi

    # Oracle
    read -p "   Želite Oracle podršku? (y/n) [n]: " oracle_choice
    oracle_choice=${oracle_choice:-n}
    if [[ "$oracle_choice" =~ ^[Yy]$ ]]; then
        log_warning "Oracle zahteva Instant Client. Instrukcije: oracle.com/technologies/instant-client"
    fi

    # MSSQL
    read -p "   Želite MSSQL podršku? (y/n) [n]: " mssql_choice
    mssql_choice=${mssql_choice:-n}
    if [[ "$mssql_choice" =~ ^[Yy]$ ]]; then
        log_warning "MSSQL zahteva FreeTDS. Instrukcije: freetds.org"
    fi
}

# Kloniranje repozitorijuma
clone_repo() {
    if [[ -d "$INSTALL_DIR" ]]; then
        log_warning "Direktorijum ${INSTALL_DIR} već postoji."
        read -p "   Da li želite da ga obrišete i klonirate ponovo? (y/n) [n]: " overwrite
        overwrite=${overwrite:-n}
        if [[ "$overwrite" =~ ^[Yy]$ ]]; then
            rm -rf "$INSTALL_DIR"
        else
            log_info "Preskačem kloniranje. Koristiće se postojeći direktorijum."
            return
        fi
    fi

    log_info "Kloniranje Kamex repozitorijuma u ${INSTALL_DIR}..."
    git clone "$REPO_URL" "$INSTALL_DIR"
    log_success "Repozitorijum je kloniran."
}

# Build i instalacija
build_and_install() {
    cd "$INSTALL_DIR"

    log_info "Pokretanje autoreconf..."
    autoreconf -fi
    log_success "autoreconf završen."

    local configure_opts="--enable-ssl"
    if dpkg -l | grep -q libmysqlclient-dev; then configure_opts+=" --with-mysql"; fi
    if dpkg -l | grep -q libpq-dev; then configure_opts+=" --with-pgsql"; fi
    if dpkg -l | grep -q libsqlite3-dev; then configure_opts+=" --with-sqlite3"; fi
    if dpkg -l | grep -q libhiredis-dev; then configure_opts+=" --with-redis"; fi

    log_info "Pokretanje ./configure sa opcijama: ${configure_opts}..."
    ./configure ${configure_opts}
    log_success "Konfiguracija završena."

    log_info "Kompajliranje (make). Ovo može potrajati..."
    make -j$(nproc)
    log_success "Kompajliranje završeno."

    log_info "Instalacija (make install-strip)..."
    make install-strip

    # libgwlib.so / libgw.so idu u $prefix/lib (npr. /usr/local/lib); bez ldconfig
    # loader često ne nalazi SONAME → greška kao kamex/systemd: libgwlib.so.0: cannot open
    if command -v ldconfig >/dev/null 2>&1; then
        log_info "Ažuriranje keša dinamičkog linkera (ldconfig)..."
        ldconfig
        log_success "ldconfig završen."
    else
        log_warning "ldconfig nije u PATH — ako bearerbox ne startuje, pokrenite ručno: ldconfig"
    fi

    log_success "Kamex je uspešno instaliran."
}

# Putanja gde je bearerbox instaliran (posle make install-strip)
kamex_sbindir() {
    if [[ -x "/usr/sbin/bearerbox" ]]; then
        echo "/usr/sbin"
    elif [[ -x "/usr/local/sbin/bearerbox" ]]; then
        echo "/usr/local/sbin"
    else
        return 1
    fi
}

# Provera da binarni fajl postoji i da ldd ne prijavljuje nedostajuće biblioteke (izbegava systemd 127)
verify_kamex_binaries() {
    local sb
    if ! sb=$(kamex_sbindir); then
        log_error "bearerbox nije pronađen u /usr/sbin ni u /usr/local/sbin posle instalacije."
        log_info "Proverite da li je 'make install-strip' prošao i koji je prefix u ./configure."
        exit 1
    fi
    log_info "Instalirani bearerbox: ${sb}/bearerbox"
    if ! command -v ldd >/dev/null 2>&1; then
        log_warning "ldd nije dostupan — preskačem proveru deljenih biblioteka."
    elif ldd "${sb}/bearerbox" 2>/dev/null | grep -q 'not found'; then
        log_error "bearerbox ima nedostajuće deljene biblioteke (ldd: 'not found'). Instalirajte runtime pakete (npr. libssl3)."
        ldd "${sb}/bearerbox" 2>/dev/null | grep 'not found' || true
        exit 1
    fi
    if [[ ! -x "${sb}/smsbox" ]]; then
        log_error "smsbox nije izvršna datoteka u ${sb}."
        exit 1
    fi
    log_success "Provera binarnih datoteka i zavisnosti je uspešna."
}

# Da li korisnik kamex može da pokrene binarne datoteke (približno kao systemd User=kamex).
# Napomena: korisnik kamex ima shell /bin/false — zato prvo su -s /bin/sh (radi bez aktivnog login shella).
# Ako preskočite: KAMEX_SKIP_USER_SMOKE=1 bash instalacija.sh
verify_kamex_user_can_run_bins() {
    if [[ -n "${KAMEX_SKIP_USER_SMOKE:-}" ]]; then
        log_warning "Preskačem proveru pokretanja kao kamex (KAMEX_SKIP_USER_SMOKE je postavljeno)."
        return 0
    fi
    local sb bearer sms last
    if ! getent passwd kamex >/dev/null 2>&1; then
        log_warning "Korisnik kamex ne postoji — preskačem proveru pokretanja kao kamex."
        return 0
    fi
    if ! sb=$(kamex_sbindir); then
        log_warning "bearerbox nije na očekivanoj putanji — preskačem proveru kao kamex."
        return 0
    fi
    sb="${sb//$'\r'/}"
    bearer="${sb}/bearerbox"
    sms="${sb}/smsbox"

    _kamex_run_help_once() {
        local bin="$1"
        last=""
        # 1) su + eksplicitna ljuska (kamex ima često /bin/false u /etc/passwd)
        if command -v su >/dev/null 2>&1; then
            last=$(su -s /bin/sh kamex -c "exec $(printf '%q' "$bin") -h" 2>&1) && return 0
        fi
        # 2) runuser (puna putanja — skripta pokrenuta kao „sudo bash“ često nema /usr/sbin u PATH)
        if [[ -x /usr/sbin/runuser ]]; then
            last=$(/usr/sbin/runuser -u kamex -- "$bin" -h 2>&1) && return 0
        fi
        if [[ -x /sbin/runuser ]]; then
            last=$(/sbin/runuser -u kamex -- "$bin" -h 2>&1) && return 0
        fi
        if command -v runuser >/dev/null 2>&1; then
            last=$(runuser -u kamex -- "$bin" -h 2>&1) && return 0
        fi
        # 3) sudo
        if command -v sudo >/dev/null 2>&1; then
            last=$(sudo -u kamex -- "$bin" -h 2>&1) && return 0
        fi
        log_error "Korisnik kamex ne može da pokrene $(basename "$bin") (su /usr/sbin/runuser / sudo)."
        if [[ -z "${last//[$'\t\n\r ']/}" ]]; then
            last="(prazan izlaz — proverite da li postoje 'su', '/usr/sbin/runuser' ili 'sudo')"
        fi
        log_info "Poslednji izlaz (stdout+stderr):"
        echo "$last" | while IFS= read -r line || [[ -n "$line" ]]; do
            echo -e "${CYAN}  |${NC} $line"
        done
        return 1
    }

    if ! _kamex_run_help_once "$bearer"; then
        exit 1
    fi
    if ! _kamex_run_help_once "$sms"; then
        exit 1
    fi
    log_success "Pokretanje bearerbox/smsbox kao korisnik kamex (-h) je uspelo."
}

# Konfiguracija
configure_kamex() {
    log_info "Podešavanje konfiguracionog direktorijuma ${CONFIG_DIR}..."
    mkdir -p "$CONFIG_DIR"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_info "Kopiranje podrazumevane konfiguracije..."
        cp "$INSTALL_DIR/doc/examples/kannel.conf" "$CONFIG_FILE"
        chmod 644 "$CONFIG_FILE"
        log_success "Podrazumevana konfiguracija je kopirana u ${CONFIG_FILE}."
        log_warning "Molimo izmenite ${CONFIG_FILE} prema vašim potrebama za SMSC konekcije."
    else
        log_info "Konfiguracioni fajl ${CONFIG_FILE} već postoji. Preskačem kopiranje."
    fi
}

# Podešavanje systemd servisa
setup_systemd() {
    log_info "Podešavanje systemd servisnih datoteka..."
    local setup_script="$INSTALL_DIR/contrib/systemd/setup-kamex-user.sh"
    if [[ -f "$setup_script" ]]; then
        chmod +x "$setup_script"                     # <-- dodata dozvola
        cd "$INSTALL_DIR/contrib/systemd"
        ./setup-kamex-user.sh
        systemctl daemon-reload
        log_success "Systemd servisne datoteke su instalirane."
        log_info "Možete ih pokrenuti sa:"
        echo "  systemctl start kamex-bearerbox"
        echo "  systemctl start kamex-smsbox"
        echo "  systemctl enable kamex-bearerbox kamex-smsbox (za automatsko pokretanje pri startu)"
    else
        log_warning "Skripta za systemd podešavanje nije pronađena. Servise možete pokrenuti ručno."
    fi
}

# Završne informacije
print_success_message() {
    echo ""
    echo "=============================================="
    echo -e "${GREEN}   Kamex SMS Gateway je uspešno instaliran!${NC}"
    echo "=============================================="
    echo ""
    echo "  ** Konfiguracija: ${CONFIG_FILE}"
    echo "  ** Admin panel:   http://localhost:13000/"
    echo "  ** HTTP API:      http://localhost:13013/"
    echo "  ** Log datoteke:  /var/log/kamex/ (ako su podešene)"
    echo "  ** Ako systemd servis padne (status=1):  journalctl -u kamex-bearerbox -e --no-pager"
    echo ""
    echo "  Brzi start (sa podrazumevanom konfiguracijom):"
    echo "    bearerbox ${CONFIG_FILE} &"
    echo "    smsbox ${CONFIG_FILE} &"
    echo ""
    echo "  Za testiranje slanja SMS-a:"
    echo "    curl \"http://localhost:13013/cgi-bin/sendsms?user=tester&pass=foobar&from=Kamex&to=+1234567890&text=Hello\""
    echo ""
    echo "  Dokumentacija: https://github.com/vaska94/Kamex"
    echo ""
}

# --- Glavni tok skripte ---
main() {
    clear
    echo "=============================================="
    echo "   Instalacija Kamex SMS Gateway na Ubuntu 22.04"
    echo "   (pokrenuto kao root korisnik)"
    echo "=============================================="
    echo ""

    check_root
    install_basic_tools
    install_dependencies
    clone_repo
    build_and_install
    verify_kamex_binaries
    configure_kamex

    echo ""
    read -p "   Želite da podesite systemd servisne datoteke? (y/n) [y]: " systemd_choice
    systemd_choice=${systemd_choice:-y}
    if [[ "$systemd_choice" =~ ^[Yy]$ ]]; then
        setup_systemd
        verify_kamex_user_can_run_bins
    else
        log_info "Systemd podešavanje je preskočeno."
    fi

    print_success_message
}

# Pokretanje
main "$@"