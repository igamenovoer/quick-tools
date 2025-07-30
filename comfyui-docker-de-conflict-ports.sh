#!/bin/bash

# This script is intended to be used with https://github.com/ai-dock/comfyui docker compose setup
# It automatically resolves port conflicts in ComfyUI environment files.
# You need to first create a ComfyUI environment file (e.g., env-1.env) with the required port variables, and use that env file with docker compose.
# for example:
# docker compose --env-file env-1.env up
# and this script will help you ensure that all ports are available and conflict-free.

# de-conflict-ports.sh - Automatically resolve port conflicts in ComfyUI env files
# Usage: ./de-conflict-ports.sh -i <input-env-file> [-o <output-env-file>] [--port-start <number>]
# 
# This script will:
# 1. Check if each port in the env file is available
# 2. If a port is in use, find the next available port
# 3. Update the env file with conflict-free ports (including comments)
# 4. Optionally start searching from a specific port number
# 5. Output to file or console

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}" >&2
}

# Function to check if a port is available
is_port_available() {
    local port=$1
    
    # Check if port is in valid range
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    
    # Check if port is available using multiple methods for reliability
    if command -v ss >/dev/null 2>&1; then
        ! ss -tuln | grep -q ":${port}\s"
    elif command -v netstat >/dev/null 2>&1; then
        ! netstat -tuln 2>/dev/null | grep -q ":${port}\s"
    else
        # Fallback: try to bind to the port
        ! nc -z 127.0.0.1 "$port" 2>/dev/null
    fi
}

# Function to find next available port
find_available_port() {
    local start_port=$1
    local current_port=$start_port
    
    while [ "$current_port" -le 65535 ]; do
        if is_port_available "$current_port"; then
            echo "$current_port"
            return 0
        fi
        ((current_port++))
    done
    
    # If we reach here, no port was found
    print_status "$RED" "ERROR: No available ports found starting from $start_port"
    return 1
}

# Function to update port in env file (both variable and comments)
update_port() {
    local env_content=$1
    local port_var=$2
    local old_port=$3
    local new_port=$4
    
    # Update the variable assignment
    env_content=$(echo "$env_content" | sed "s/^${port_var}=.*/${port_var}=${new_port}/")
    
    # Update port numbers in comments (be careful to only update relevant ones)
    case "$port_var" in
        "SSH_PORT_HOST")
            env_content=$(echo "$env_content" | sed "s/localhost:${old_port}/localhost:${new_port}/g")
            ;;
        "SERVICEPORTAL_PORT_HOST")
            env_content=$(echo "$env_content" | sed "s/localhost:${old_port}/localhost:${new_port}/g")
            ;;
        "COMFYUI_PORT_HOST")
            env_content=$(echo "$env_content" | sed "s/localhost:${old_port}/localhost:${new_port}/g")
            ;;
        "JUPYTER_PORT_HOST")
            env_content=$(echo "$env_content" | sed "s/localhost:${old_port}/localhost:${new_port}/g")
            ;;
        "SYNCTHING_UI_PORT_HOST")
            env_content=$(echo "$env_content" | sed "s/localhost:${old_port}/localhost:${new_port}/g")
            ;;
    esac
    
    echo "$env_content"
}

# Function to extract current port value from env content
get_current_port() {
    local env_content=$1
    local port_var=$2
    
    echo "$env_content" | grep "^${port_var}=" | cut -d'=' -f2 | tr -d ' '
}

# Function to show usage
show_usage() {
    echo "Usage: $0 -i <input-file> [-o <output-file>] [--port-start <number>]"
    echo ""
    echo "Required options:"
    echo "  -i, --input <file>       Input environment file"
    echo ""
    echo "Optional options:"
    echo "  -o, --output <file>      Output environment file (if not specified, prints to console)"
    echo "  --port-start <number>    Start searching for ports from this number (default: use existing ports)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -i env-1.env                           # Check ports, output to console"
    echo "  $0 -i env-1.env -o env-fixed.env          # Check ports, save to new file"
    echo "  $0 -i env-1.env --port-start 9000         # Start all ports from 9000+, output to console"
    echo "  $0 -i env-1.env -o env-9000.env --port-start 9000  # Start from 9000+, save to file"
}

# Main function
main() {
    local input_file=""
    local output_file=""
    local port_start=""
    local use_custom_start=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--input)
                input_file="$2"
                shift 2
                ;;
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            --port-start)
                port_start="$2"
                use_custom_start=true
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_status "$RED" "ERROR: Unknown option $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate input
    if [ -z "$input_file" ]; then
        print_status "$RED" "ERROR: Input file is required"
        show_usage
        exit 1
    fi
    
    if [ ! -f "$input_file" ]; then
        print_status "$RED" "ERROR: Input file '$input_file' not found"
        exit 1
    fi
    
    # Validate port_start if provided
    if [ "$use_custom_start" = true ]; then
        if ! [[ "$port_start" =~ ^[0-9]+$ ]] || [ "$port_start" -lt 1024 ] || [ "$port_start" -gt 65535 ]; then
            print_status "$RED" "ERROR: Invalid port start number. Must be between 1024-65535"
            exit 1
        fi
    fi
    
    print_status "$BLUE" "=== ComfyUI Port Conflict Resolution ==="
    print_status "$BLUE" "Input file: $input_file"
    
    if [ -n "$output_file" ]; then
        print_status "$BLUE" "Output file: $output_file"
    else
        print_status "$BLUE" "Output: console"
    fi
    
    if [ "$use_custom_start" = true ]; then
        print_status "$BLUE" "Custom port start: $port_start"
    fi
    
    # Define port variables to check (in order of preference)
    local port_vars=(
        "SSH_PORT_HOST"
        "SERVICEPORTAL_PORT_HOST"
        "SERVICEPORTAL_METRICS_PORT"
        "COMFYUI_PORT_HOST"
        "COMFYUI_METRICS_PORT"
        "JUPYTER_PORT_HOST"
        "JUPYTER_METRICS_PORT"
        "SYNCTHING_UI_PORT_HOST"
        "SYNCTHING_TRANSPORT_PORT_HOST"
    )
    
    # Read the entire file content
    local env_content
    env_content=$(cat "$input_file")
    
    local changes_made=false
    local current_port_start=$port_start
    
    print_status "$YELLOW" "\nChecking ports..."
    
    for port_var in "${port_vars[@]}"; do
        local current_port
        current_port=$(get_current_port "$env_content" "$port_var")
        
        if [ -z "$current_port" ]; then
            print_status "$YELLOW" "⚠️  $port_var: not found in env file, skipping"
            continue
        fi
        
        local target_port=$current_port
        
        # If using custom start, override the target port
        if [ "$use_custom_start" = true ]; then
            target_port=$current_port_start
        fi
        
        # Check if target port is available
        if is_port_available "$target_port"; then
            if [ "$target_port" != "$current_port" ]; then
                print_status "$GREEN" "✓ $port_var: $current_port → $target_port (updated)"
                env_content=$(update_port "$env_content" "$port_var" "$current_port" "$target_port")
                changes_made=true
            else
                print_status "$GREEN" "✓ $port_var: $current_port (available)"
            fi
        else
            # Find next available port
            local new_port
            new_port=$(find_available_port "$target_port")
            
            if [ $? -eq 0 ]; then
                print_status "$YELLOW" "⚠️  $port_var: $current_port → $new_port (conflict resolved)"
                env_content=$(update_port "$env_content" "$port_var" "$current_port" "$new_port")
                changes_made=true
            else
                print_status "$RED" "❌ $port_var: Could not find available port starting from $target_port"
                exit 1
            fi
        fi
        
        # Update current_port_start for next iteration if using custom start
        if [ "$use_custom_start" = true ]; then
            current_port_start=$((target_port + 1))
        fi
    done
    
    print_status "$BLUE" "\n=== Summary ==="
    
    if [ "$changes_made" = true ]; then
        print_status "$GREEN" "✓ Port conflicts resolved successfully!"
    else
        print_status "$GREEN" "✓ No port conflicts found. All ports are available!"
    fi
    
    # Output the result
    if [ -n "$output_file" ]; then
        echo "$env_content" > "$output_file"
        print_status "$BLUE" "Updated environment saved to: $output_file"
        print_status "$YELLOW" "Review the changes and test your configuration:"
        print_status "$YELLOW" "  docker compose --env-file $output_file config"
        print_status "$BLUE" "\nTo start ComfyUI with the updated configuration:"
        print_status "$BLUE" "  docker compose --env-file $output_file up"
    else
        # Output to console
        print_status "$BLUE" "\n=== Generated Environment File ==="
        echo "$env_content"
    fi
}

# Check if script is being run directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
