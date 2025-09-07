#!/bin/bash
# openfortivpn-macosx Common Functions Library
# Shared functions used by all scripts

# ============================================================================
# Configuration Loading
# ============================================================================

# Helper print functions
print_success() { echo -e "${GREEN}$1${NC}"; }
print_warning() { echo -e "${YELLOW}$1${NC}"; }
print_error() { echo -e "${RED}$1${NC}"; }
print_info() { echo -e "${BLUE}$1${NC}"; }
print_status() { echo -e "${CYAN}$1${NC}"; }
print_header() { echo -e "${PURPLE}$1${NC}"; }

# Load configuration from multiple possible locations
load_config() {
    local config_loaded=false
    local config_locations=(
        "/usr/local/etc/openfortivpn-macosx/config.sh"
    )
    
    for config_file in "${config_locations[@]}"; do
        if [[ -f "$config_file" ]]; then
            source "$config_file"
            config_loaded=true
            break
        fi
    done
    
    if [[ "$config_loaded" == "false" ]]; then
        # Set defaults if no config file found
        set_default_config
        # print in orange
    fi
}

# Set default configuration values
set_default_config() {
    # VPN Configuration
    VPN_SERVER="${VPN_SERVER:-vpn.internal.local}"
    VPN_PORT="${VPN_PORT:-12345}"
    
    # DNS Configuration
    if [[ -z "${SEARCH_DOMAINS[@]}" ]]; then
        SEARCH_DOMAINS=("internal.local" "private.domain")
    fi
    
    # File Paths
    PID_FILE="${PID_FILE:-/var/run/openfortivpn-macosx.pid}"
    LOG_FILE="${LOG_FILE:-/var/log/openfortivpn-macosx.log}"
    ROUTES_FILE="${ROUTES_FILE:-/var/run/openfortivpn-macosx.routes}"
    
    # OpenFortiVPN
    OPENFORTIVPN_BIN="${OPENFORTIVPN_BIN:-$(which openfortivpn || echo /opt/homebrew/bin/openfortivpn)}"
    
    # SAML
    BROWSER_USER="${BROWSER_USER:-${SUDO_USER:-${USER}}}"
    SAML_TIMEOUT="${SAML_TIMEOUT:-10}"

    # PPP Configuration
    MIN_ROUTES_THRESHOLD="${MIN_ROUTES_THRESHOLD:-5}"
    
    # Debug
    DEBUG_ENABLED="${DEBUG_ENABLED:-false}"
    KEEP_TEMP_FILES="${KEEP_TEMP_FILES:-false}"
}

# ============================================================================
# Logging Functions
# ============================================================================

# Generic logging function
log_message() {
    local prefix="${2:-INFO}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$prefix] $1" >> "$LOG_FILE"
    if [[ "$DEBUG_ENABLED" == "true" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [$prefix] $1" >&2
    fi
}

# Log error messages
log_error() {
    log_message "$1" "ERROR"
}

# Log debug messages (only if debug is enabled)
log_debug() {
    if [[ "$DEBUG_ENABLED" == "true" ]]; then
        log_message "$1" "DEBUG"
    fi
}

# Log PPP-specific messages
log_ppp() {
    local script_type="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [PPP $script_type] $message" >> "$LOG_FILE"
}

# ============================================================================
# DNS Management Functions
# ============================================================================

# Modify DNS search domains (add or remove)
modify_search_domains() {
    local action="$1" # "add" or "remove"
    local action_text="Adding"
    [[ "$action" == "remove" ]] && action_text="Removing"
    
    log_message "${action_text} DNS search domains..."
    
    /usr/sbin/networksetup -listallnetworkservices | grep -v "\*" | while IFS= read -r service; do
        [[ -z "$service" || "$service" == "An asterisk" ]] && continue
        
        # Get current domains, filter out empty responses
        local current=$(/usr/sbin/networksetup -getsearchdomains "$service" 2>/dev/null)
        [[ "$current" == *"Search Domains"* ]] && current=""
        
        # Build new domain list using arrays
        local domains=()
        
        if [[ "$action" == "add" ]]; then
            # Add existing domains first
            if [[ -n "$current" ]]; then
                while IFS= read -r domain; do
                    [[ -n "$domain" ]] && domains+=("$domain")
                done <<< "$current"
            fi
            
            # Add new domains (no duplicates)
            for domain in "${SEARCH_DOMAINS[@]}"; do
                local found=false
                for existing in "${domains[@]}"; do
                    [[ "$existing" == "$domain" ]] && found=true && break
                done
                [[ "$found" == false ]] && domains+=("$domain")
            done
        else
            # Remove specified domains, keep others
            if [[ -n "$current" ]]; then
                while IFS= read -r domain; do
                    if [[ -n "$domain" ]]; then
                        local keep=true
                        for remove_domain in "${SEARCH_DOMAINS[@]}"; do
                            [[ "$domain" == "$remove_domain" ]] && keep=false && break
                        done
                        [[ "$keep" == true ]] && domains+=("$domain")
                    fi
                done <<< "$current"
            fi
        fi
        
        # Apply changes and log result
        local result
        if [[ ${#domains[@]} -gt 0 ]]; then
            result=$(/usr/sbin/networksetup -setsearchdomains "$service" "${domains[@]}" 2>&1)
        else
            result=$(/usr/sbin/networksetup -setsearchdomains "$service" "Empty" 2>&1)
        fi
        
        # Only log if there's actual output and it's not just success
        [[ -n "$result" && "$result" != "" ]] && log_debug "DNS update for $service: $result"
    done
}

# Flush DNS cache
flush_dns_cache() {
    log_message "Flushing DNS cache..."
    /usr/bin/dscacheutil -flushcache 2>&1 || true
    /usr/bin/killall -HUP mDNSResponder 2>&1 || true
}

# ============================================================================
# Network Utility Functions
# ============================================================================

# Convert netmask to CIDR notation
mask_to_cidr() {
    local mask="$1"
    local cidr=0
    
    # Convert dotted decimal to 32-bit integer
    IFS='.' read -r a b c d <<< "$mask"
    local int_mask=$(( (a << 24) + (b << 16) + (c << 8) + d ))
    
    # Count consecutive 1 bits from the left
    local temp=$int_mask
    while (( temp & 0x80000000 )); do
        ((cidr++))
        temp=$((temp << 1))
    done
    
    # Verify it's a valid netmask (no holes in the bit pattern)
    local expected_mask=$(( (0xFFFFFFFF << (32 - cidr)) & 0xFFFFFFFF ))
    
    if (( int_mask == expected_mask )); then
        echo "$cidr"
    else
        echo ""  # Invalid netmask
    fi
}

# ============================================================================
# Session Management Functions
# ============================================================================

# Generate unique session ID
generate_session_id() {
    echo "$(date +%s)-$$-$(openssl rand -hex 4)"
}

# Mark session start in log
mark_session_start() {
    local session_id="$1"
    local session_marker="=== VPN SESSION START [$session_id]: $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "$session_marker" >> "$LOG_FILE"
}

# Mark session end in log
mark_session_end() {
    local session_id="$1"
    local session_marker="=== VPN SESSION END [$session_id]: $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "$session_marker" >> "$LOG_FILE"
}

# ============================================================================
# Route Management Functions
# ============================================================================

# Extract VPN routes from XML configuration
extract_routes_from_xml() {
    local session_id="$1"
    local xml_config=""
    local routes_found=false
    
    log_debug "Looking for XML routes for session: $session_id"
    
    if [[ -n "$session_id" ]]; then
        # Find the session marker in the log
        local session_marker="VPN SESSION START \[$session_id\]"
        
        # Extract all content after the session marker
        local session_log=$(sed -n "/$session_marker/,\$p" "$LOG_FILE" 2>/dev/null)
        
        if [[ -n "$session_log" ]]; then
            # Look for ALL XML configurations in this session
            local best_xml=""
            local best_route_count=0
            
            while IFS= read -r xml_line; do
                if [[ -n "$xml_line" ]]; then
                    # Count routes in this XML
                    local route_count=$(echo "$xml_line" | grep -o '<addr ip=' | wc -l | tr -d ' ')
                    log_debug "Found XML with $route_count routes"
                    
                    # Keep the XML with the most routes
                    if [[ $route_count -gt $best_route_count ]]; then
                        best_xml="$xml_line"
                        best_route_count=$route_count
                    fi
                fi
            done < <(echo "$session_log" | grep -o '<?xml version.*</sslvpn-tunnel>')
            
            # Only use XML if it has enough routes
            if [[ $best_route_count -ge $MIN_ROUTES_THRESHOLD ]]; then
                xml_config="$best_xml"
                routes_found=true
                log_message "Using XML with $best_route_count routes"
            else
                log_debug "No XML with sufficient routes found (best had $best_route_count)"
            fi
        fi
    fi
    
    # Return the XML config
    echo "$xml_config"
    [[ "$routes_found" == "true" ]] && return 0 || return 1
}

# Add a single route
add_route() {
    local ip="$1"
    local mask="$2"
    local interface="$3"
    
    local cidr=$(mask_to_cidr "$mask")
    
    if [[ "$mask" == "255.255.255.255" ]]; then
        # Host route
        log_debug "Adding host route: $ip via $interface"
        /sbin/route add -host "$ip" -interface "$interface" 2>&1 || true
    elif [[ -n "$cidr" ]]; then
        # Network route with CIDR
        log_debug "Adding network route: $ip/$cidr via $interface"
        /sbin/route add -net "$ip/$cidr" -interface "$interface" 2>&1 || true
    else
        # Network route with mask
        log_debug "Adding network route: $ip mask $mask via $interface"
        /sbin/route add -net "$ip" "$mask" -interface "$interface" 2>&1 || true
    fi
}

# Remove default route from PPP interface
remove_ppp_default_route() {
    local interface="$1"
    log_message "Removing default route from $interface..."
    /sbin/route delete -net default -ifscope "$interface" 2>&1 || true
}

# ============================================================================
# Process Management Functions
# ============================================================================

# Check if process is running
is_process_running() {
    local pid="$1"
    ps -p "$pid" > /dev/null 2>&1
}

# Kill process with timeout
kill_process_with_timeout() {
    local pid="$1"
    local timeout="${2:-5}"
    
    if is_process_running "$pid"; then
        kill "$pid" 2>/dev/null
        
        local count=0
        while [[ $count -lt $timeout ]] && is_process_running "$pid"; do
            sleep 1
            ((count++))
        done
        
        # Force kill if still running
        if is_process_running "$pid"; then
            kill -9 "$pid" 2>/dev/null
            sleep 1
        fi
        
        ! is_process_running "$pid"
    else
        return 0
    fi
}

# Find processes by pattern
find_processes_by_pattern() {
    local pattern="$1"
    ps aux | grep "$pattern" | grep -v grep | awk '{print $2}'
}

# ============================================================================
# Cleanup Functions
# ============================================================================

# Clean up temporary files
cleanup_temp_files() {
    if [[ "$KEEP_TEMP_FILES" != "true" ]]; then
        log_debug "Cleaning up temporary files..."
        [[ -f "$ROUTES_FILE" ]] && rm -f "$ROUTES_FILE"
        [[ -f "$PID_FILE" ]] && rm -f "$PID_FILE"
    fi
}