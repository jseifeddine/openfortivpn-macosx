# openfortivpn-macosx

A macOS wrapper for openfortivpn that provides proper route management, DNS configuration, and auto browser open for SAML authentication.

Tested with `Mac OS X 15.6.1` and `openfortivpn 1.23.1`

## Features

- **Automatic Route Management**: Prevents PPP from hijacking the default route
- **DNS Search Domain Management**: Automatically adds/removes search domains on connect/disconnect
- **SAML Authentication Support**: Opens browser automatically for SAML login
- **Route Persistence**: Extracts and applies VPN routes from FortiGate XML configuration
- **Modular Configuration**: Single configuration file for all settings
- **Shared Functions Library**: Common functions shared between all scripts

## Prerequisites

- macOS (tested on macOS 15+)
- openfortivpn installed (`brew install openfortivpn`)
- Root/sudo access for VPN operations

## Installation

### Quick Install

```bash
# Clone the repository
git clone https://github.com/jseifeddine/openfortivpn-macosx.git
cd openfortivpn-macosx

# Run the installer (requires sudo)
sudo ./install.sh
```

### Manual Installation

1. Copy the main script:
```bash
sudo cp openfortivpn-macosx /usr/local/bin/
sudo chmod 755 /usr/local/bin/openfortivpn-macosx
```

2. Install the library:
```bash
sudo mkdir -p /usr/local/lib/openfortivpn-macosx
sudo cp lib/functions.sh /usr/local/lib/openfortivpn-macosx/
```

3. Install PPP scripts:
```bash
sudp cp /etc/ppp/ip-up /etc/ppp/ip-up.bak
sudp cp /etc/ppp/ip-down /etc/ppp/ip-down.bak
sudo cp ppp/ip-up /etc/ppp/ip-up
sudo cp ppp/ip-down /etc/ppp/ip-down
sudo chmod 755 /etc/ppp/ip-up /etc/ppp/ip-down
```

4. Install configuration:
```bash
sudo mkdir -p /usr/local/etc/openfortivpn-macosx
sudo cp config.sh.example /usr/local/etc/openfortivpn-macosx/config.sh
```

5. Install sudoers configuration:
```bash
# Copy the sudoers file
sudo cp sudoers.d/openfortivpn-macosx /etc/sudoers.d/

# Edit the file to replace 'jseifeddine' with your username
sudo nano /etc/sudoers.d/openfortivpn-macosx
```

**Important**: Replace `jseifeddine` in the sudoers file with your actual username. The file should contain entries like:
```
yourusername ALL= NOPASSWD: /usr/local/bin/openfortivpn-macosx
yourusername ALL= NOPASSWD: /usr/sbin/networksetup
yourusername ALL= NOPASSWD: /usr/bin/dscacheutil
yourusername ALL= NOPASSWD: /usr/bin/killall
```

6. Add shell alias to `~/.zshrc`:
```bash
alias vpn='sudo /usr/local/bin/openfortivpn-macosx'
```

## Configuration

The configuration file is searched in the following locations (in order):
1. `/usr/local/etc/openfortivpn-macosx/config.sh`

Edit the configuration file to set your VPN server details:
```bash
sudo nano /usr/local/etc/openfortivpn-macosx/config.sh
```

Key configuration options:

```bash
# VPN Server Configuration
VPN_SERVER="your.vpn.server.com"
VPN_PORT="443"

# DNS Search Domains
SEARCH_DOMAINS=(
    "internal.domain.com"
    "dev.domain.com"
)

# openfortivpn Binary Path
OPENFORTIVPN_BIN="/usr/local/bin/openfortivpn"
```

## Usage

### Basic Commands

```bash
# Start VPN connection
vpn start

# Stop VPN connection
vpn stop

# Check VPN status
vpn status

# Restart VPN connection
vpn restart

# Tail log file
vpn logs
```

## How It Works

### Architecture

```
openfortivpn-macosx (main script)
├── lib/functions.sh (shared functions)
├── config.sh (configuration)
├── ppp/ip-up (called on connection)
└── ppp/ip-down (called on disconnect)
```

### Connection Flow

1. **Start Command**: Main script generates a unique session ID and starts openfortivpn
2. **SAML Authentication**: Automatically opens browser for SAML login
3. **PPP ip-up**: Extracts routes from FortiGate XML and applies them
4. **DNS Configuration**: Adds search domains to all network interfaces
5. **PPP ip-down**: Removes search domains and cleans up on disconnect

### Route Management

The script extracts routes from the FortiGate XML configuration that openfortivpn receives. These routes are:
- Parsed from the XML response
- Saved to a JSON file for persistence
- Applied using the macOS `route` command

## File Locations

- **Main Script**: `/usr/local/bin/openfortivpn-macosx`
- **Configuration**: `/usr/local/etc/openfortivpn-macosx/config.sh`
- **Library**: `/usr/local/lib/openfortivpn-macosx/functions.sh`
- **PPP Scripts**: `/etc/ppp/ip-up`, `/etc/ppp/ip-down`
- **Log File**: `/var/log/openfortivpn-macosx.log`
- **Routes File**: `/var/run/openfortivpn-macosx.routes`
- **PID Files**: `/var/run/openfortivpn-macosx.pid`

## Troubleshooting

### VPN won't start
- Check that openfortivpn is installed: `which openfortivpn`
- Verify configuration file exists and is readable
- Check log file: `sudo tail -f /var/log/openfortivpn-macosx.log`

### Routes not being applied
- Ensure minimum routes threshold is appropriate (default: 5)
- Check that XML parsing is working in the log file
- Verify PPP scripts have execute permissions

### DNS issues
- Check that search domains are correctly configured
- Verify network services are being updated: `networksetup -getsearchdomains "Wi-Fi"`
- Try manually flushing DNS: `sudo dscacheutil -flushcache`

## Advanced Configuration

### Custom openfortivpn Options

Edit the configuration file to add custom openfortivpn options:

For full config options see: [openfortivpn on GitHub](https://github.com/adrienverge/openfortivpn/blob/624e45753752e5fd1e7a32197193247709e80aa0/src/main.c)  
```bash
OPENFORTIVPN_OPTIONS=(
    "--saml-login -vvvv"                      # Use SAML authentication and verbose logging to capture XML routes
    "--set-dns=0"                # Don't let openfortivpn set DNS
    "--set-routes=0"             # Don't let openfortivpn set routes
    "--pppd-accept-remote=0"     # Don't accept remote IP
    "--pppd-no-peerdns"          # Don't use peer DNS
    # THIS IS BROKEN ON MAC ?? "--persistent=10"            # Reconnect after 10 seconds on disconnect
)
```

### Debug Mode

Enable debug logging in the configuration:

```bash
DEBUG_ENABLED=true
KEEP_TEMP_FILES=true
```

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.

## License

This project is provided as-is for community use. Feel free to modify and distribute as needed.

## Credits

Built on top of [openfortivpn](https://github.com/adrienverge/openfortivpn) - an open-source VPN client for FortiGate.