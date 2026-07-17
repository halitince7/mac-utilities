#!/bin/bash

# Mac Desktop Utilities Service Manager
# Manages desktop-switcher and scrollfix services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Service configurations
DESKTOP_SWITCHER_SERVICE="com.user.desktopswitcher"
DESKTOP_SWITCHER_BINARY="desktop-switcher"
DESKTOP_SWITCHER_SOURCE="desktop-switcher.swift"

SCROLLFIX_SERVICE="com.user.scrollfix"
SCROLLFIX_BINARY="scrollfix"
SCROLLFIX_SOURCE="scrollfix.swift"

INSTALL_DIR="/usr/local/bin"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

# Helper functions
print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Check if running from correct directory
check_directory() {
    # Check if we're in the root directory or scripts directory
    if [[ -f "src/$DESKTOP_SWITCHER_SOURCE" && -f "src/$SCROLLFIX_SOURCE" ]]; then
        # We're in root directory
        DESKTOP_SWITCHER_SOURCE="src/$DESKTOP_SWITCHER_SOURCE"
        SCROLLFIX_SOURCE="src/$SCROLLFIX_SOURCE"
    elif [[ -f "../src/$DESKTOP_SWITCHER_SOURCE" && -f "../src/$SCROLLFIX_SOURCE" ]]; then
        # We're in scripts directory
        DESKTOP_SWITCHER_SOURCE="../src/$DESKTOP_SWITCHER_SOURCE"
        SCROLLFIX_SOURCE="../src/$SCROLLFIX_SOURCE"
    else
        print_error "Swift source files not found!"
        print_info "Please run this script from the mac-desktop-switcher directory or scripts directory."
        exit 1
    fi
}

# Check if Swift compiler is available
check_swift() {
    if ! command -v swiftc &> /dev/null; then
        print_error "Swift compiler not found!"
        print_info "Please install Xcode or Command Line Tools: xcode-select --install"
        exit 1
    fi
}

# Compile a Swift source file
compile_service() {
    local source_file=$1
    local binary_name=$2
    
    print_info "Compiling $source_file..."
    if swiftc -o "$binary_name" "$source_file"; then
        print_success "Compiled $binary_name successfully"
    else
        print_error "Failed to compile $source_file"
        exit 1
    fi
}

# Install binary to system directory
install_binary() {
    local binary_name=$1
    
    if [[ -f "$binary_name" ]]; then
        print_info "Installing $binary_name to $INSTALL_DIR..."
        if sudo mv "$binary_name" "$INSTALL_DIR/"; then
            print_success "Installed $binary_name to $INSTALL_DIR"
        else
            print_error "Failed to install $binary_name"
            exit 1
        fi
    else
        print_error "Binary $binary_name not found!"
        exit 1
    fi
}

# Create launch agent plist file
create_launch_agent() {
    local service_name=$1
    local binary_name=$2
    local plist_file="$LAUNCH_AGENTS_DIR/$service_name.plist"
    
    # Create LaunchAgents directory if it doesn't exist
    mkdir -p "$LAUNCH_AGENTS_DIR"
    
    print_info "Creating launch agent for $service_name..."
    
    cat > "$plist_file" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$service_name</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/$binary_name</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOL
    
    print_success "Created launch agent: $plist_file"
}

# Load and start a service
start_service() {
    local service_name=$1
    local plist_file="$LAUNCH_AGENTS_DIR/$service_name.plist"
    
    if [[ -f "$plist_file" ]]; then
        print_info "Starting service $service_name..."
        if launchctl load "$plist_file" 2>/dev/null; then
            print_success "Service $service_name started successfully"
        else
            print_warning "Service $service_name may already be running or failed to start"
        fi
    else
        print_error "Launch agent file not found: $plist_file"
        print_info "Please create the service first using: $0 create $service_name"
        exit 1
    fi
}

# Stop and unload a service
stop_service() {
    local service_name=$1
    local plist_file="$LAUNCH_AGENTS_DIR/$service_name.plist"
    
    if [[ -f "$plist_file" ]]; then
        print_info "Stopping service $service_name..."
        if launchctl unload "$plist_file" 2>/dev/null; then
            print_success "Service $service_name stopped successfully"
        else
            print_warning "Service $service_name may not be running"
        fi
    else
        print_error "Launch agent file not found: $plist_file"
        exit 1
    fi
}

# Delete a service completely
delete_service() {
    local service_name=$1
    local binary_name=$2
    local plist_file="$LAUNCH_AGENTS_DIR/$service_name.plist"
    local binary_file="$INSTALL_DIR/$binary_name"
    
    print_info "Deleting service $service_name..."
    
    # Stop the service first
    if [[ -f "$plist_file" ]]; then
        launchctl unload "$plist_file" 2>/dev/null || true
        rm "$plist_file"
        print_success "Removed launch agent: $plist_file"
    fi
    
    # Remove the binary
    if [[ -f "$binary_file" ]]; then
        sudo rm "$binary_file"
        print_success "Removed binary: $binary_file"
    fi
    
    print_success "Service $service_name deleted completely"
}

# Check service status
check_service_status() {
    local service_name=$1
    local plist_file="$LAUNCH_AGENTS_DIR/$service_name.plist"
    local binary_name=$2
    local binary_file="$INSTALL_DIR/$binary_name"
    
    echo -e "${BLUE}Status for $service_name:${NC}"
    
    # Check if plist exists
    if [[ -f "$plist_file" ]]; then
        print_success "Launch agent exists: $plist_file"
    else
        print_error "Launch agent missing: $plist_file"
    fi
    
    # Check if binary exists
    if [[ -f "$binary_file" ]]; then
        print_success "Binary exists: $binary_file"
    else
        print_error "Binary missing: $binary_file"
    fi
    
    # Check if service is loaded
    if launchctl list | grep -q "$service_name"; then
        print_success "Service is loaded and running"
    else
        print_warning "Service is not loaded/running"
    fi
    
    echo
}

# Create a complete service (compile + install + create launch agent + start)
create_service() {
    local service_type=$1
    
    case $service_type in
        "desktop-switcher"|"ds")
            print_header "Creating Desktop Switcher Service"
            compile_service "$DESKTOP_SWITCHER_SOURCE" "$DESKTOP_SWITCHER_BINARY"
            install_binary "$DESKTOP_SWITCHER_BINARY"
            create_launch_agent "$DESKTOP_SWITCHER_SERVICE" "$DESKTOP_SWITCHER_BINARY"
            start_service "$DESKTOP_SWITCHER_SERVICE"
            print_permissions_info "desktop-switcher"
            ;;
        "scrollfix"|"sf")
            print_header "Creating ScrollFix Service"
            compile_service "$SCROLLFIX_SOURCE" "$SCROLLFIX_BINARY"
            install_binary "$SCROLLFIX_BINARY"
            create_launch_agent "$SCROLLFIX_SERVICE" "$SCROLLFIX_BINARY"
            start_service "$SCROLLFIX_SERVICE"
            print_permissions_info "scrollfix"
            ;;
        "both"|"all")
            create_service "desktop-switcher"
            echo
            create_service "scrollfix"
            ;;
        *)
            print_error "Unknown service type: $service_type"
            print_usage
            exit 1
            ;;
    esac
}

# Print permissions information
print_permissions_info() {
    local service_name=$1
    
    print_header "Required Permissions for $service_name"
    print_warning "You need to grant permissions manually:"
    echo "1. Go to System Settings → Privacy & Security → Accessibility"
    echo "2. Find '$service_name' in the list and enable it"
    
    if [[ "$service_name" == "scrollfix" ]]; then
        echo "3. Also go to System Settings → Privacy & Security → Input Monitoring"
        echo "4. Find 'scrollfix' in the list and enable it"
    fi
    
    print_info "The service may not work properly until permissions are granted."
    echo
}

# Print usage information
print_usage() {
    echo "Usage: $0 <command> [service]"
    echo
    echo "Commands:"
    echo "  create <service>  - Compile, install, and start a service"
    echo "  start <service>   - Start a service"
    echo "  stop <service>    - Stop a service"
    echo "  delete <service>  - Completely remove a service"
    echo "  status [service]  - Show service status"
    echo "  help             - Show this help message"
    echo
    echo "Services:"
    echo "  desktop-switcher, ds  - Desktop switcher service"
    echo "  scrollfix, sf         - ScrollFix service"
    echo "  both, all            - Both services (for create command only)"
    echo
    echo "Examples:"
    echo "  $0 create both              # Create both services"
    echo "  $0 create desktop-switcher  # Create only desktop switcher"
    echo "  $0 start scrollfix          # Start scrollfix service"
    echo "  $0 stop ds                  # Stop desktop switcher"
    echo "  $0 delete sf                # Delete scrollfix service"
    echo "  $0 status                   # Show status of both services"
}

# Main script logic
main() {
    if [[ $# -eq 0 ]]; then
        print_usage
        exit 1
    fi
    
    local command=$1
    local service=${2:-""}
    
    case $command in
        "create")
            if [[ -z "$service" ]]; then
                print_error "Service name required for create command"
                print_usage
                exit 1
            fi
            check_directory
            check_swift
            create_service "$service"
            ;;
        "start")
            if [[ -z "$service" ]]; then
                print_error "Service name required for start command"
                print_usage
                exit 1
            fi
            case $service in
                "desktop-switcher"|"ds")
                    start_service "$DESKTOP_SWITCHER_SERVICE"
                    ;;
                "scrollfix"|"sf")
                    start_service "$SCROLLFIX_SERVICE"
                    ;;
                "both"|"all")
                    start_service "$DESKTOP_SWITCHER_SERVICE"
                    start_service "$SCROLLFIX_SERVICE"
                    ;;
                *)
                    print_error "Unknown service: $service"
                    print_usage
                    exit 1
                    ;;
            esac
            ;;
        "stop")
            if [[ -z "$service" ]]; then
                print_error "Service name required for stop command"
                print_usage
                exit 1
            fi
            case $service in
                "desktop-switcher"|"ds")
                    stop_service "$DESKTOP_SWITCHER_SERVICE"
                    ;;
                "scrollfix"|"sf")
                    stop_service "$SCROLLFIX_SERVICE"
                    ;;
                "both"|"all")
                    stop_service "$DESKTOP_SWITCHER_SERVICE"
                    stop_service "$SCROLLFIX_SERVICE"
                    ;;
                *)
                    print_error "Unknown service: $service"
                    print_usage
                    exit 1
                    ;;
            esac
            ;;
        "delete")
            if [[ -z "$service" ]]; then
                print_error "Service name required for delete command"
                print_usage
                exit 1
            fi
            case $service in
                "desktop-switcher"|"ds")
                    delete_service "$DESKTOP_SWITCHER_SERVICE" "$DESKTOP_SWITCHER_BINARY"
                    ;;
                "scrollfix"|"sf")
                    delete_service "$SCROLLFIX_SERVICE" "$SCROLLFIX_BINARY"
                    ;;
                "both"|"all")
                    delete_service "$DESKTOP_SWITCHER_SERVICE" "$DESKTOP_SWITCHER_BINARY"
                    delete_service "$SCROLLFIX_SERVICE" "$SCROLLFIX_BINARY"
                    ;;
                *)
                    print_error "Unknown service: $service"
                    print_usage
                    exit 1
                    ;;
            esac
            ;;
        "status")
            if [[ -z "$service" ]]; then
                # Show status for both services
                check_service_status "$DESKTOP_SWITCHER_SERVICE" "$DESKTOP_SWITCHER_BINARY"
                check_service_status "$SCROLLFIX_SERVICE" "$SCROLLFIX_BINARY"
            else
                case $service in
                    "desktop-switcher"|"ds")
                        check_service_status "$DESKTOP_SWITCHER_SERVICE" "$DESKTOP_SWITCHER_BINARY"
                        ;;
                    "scrollfix"|"sf")
                        check_service_status "$SCROLLFIX_SERVICE" "$SCROLLFIX_BINARY"
                        ;;
                    *)
                        print_error "Unknown service: $service"
                        print_usage
                        exit 1
                        ;;
                esac
            fi
            ;;
        "help"|"-h"|"--help")
            print_usage
            ;;
        *)
            print_error "Unknown command: $command"
            print_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
