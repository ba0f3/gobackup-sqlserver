#!/bin/bash
# GoBackup SQL Server Entrypoint Script
# Initializes the container, validates configuration, and starts GoBackup

# Exit immediately if a command exits with a non-zero status
set -e

# Logging functions for consistent output formatting
log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_warning() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARNING] $*" >&2
}

# Main execution starts here
log_info "Starting GoBackup SQL Server container"

# Validate required environment variables
validate_required_env() {
    log_info "Validating required environment variables"
    
    local missing_vars=()
    
    # Required MSSQL variables
    if [ -z "${MSSQL_HOST}" ]; then
        missing_vars+=("MSSQL_HOST")
    fi
    
    if [ -z "${MSSQL_DATABASE}" ]; then
        missing_vars+=("MSSQL_DATABASE")
    fi
    
    if [ -z "${MSSQL_PASSWORD}" ]; then
        missing_vars+=("MSSQL_PASSWORD")
    fi
    
    # Required MinIO variables
    if [ -z "${MINIO_ENDPOINT}" ]; then
        missing_vars+=("MINIO_ENDPOINT")
    fi
    
    if [ -z "${MINIO_BUCKET}" ]; then
        missing_vars+=("MINIO_BUCKET")
    fi
    
    if [ -z "${MINIO_ACCESS_KEY}" ]; then
        missing_vars+=("MINIO_ACCESS_KEY")
    fi
    
    if [ -z "${MINIO_SECRET_KEY}" ]; then
        missing_vars+=("MINIO_SECRET_KEY")
    fi
    
    # Check if any variables are missing
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            log_error "  - ${var}"
        done
        log_error "Please set all required environment variables and try again"
        exit 1
    fi
    
    log_info "All required environment variables are set"
}

# Generate GoBackup configuration file from template
generate_config() {
    log_info "Generating GoBackup configuration file"
    
    local template_file="/app/gobackup.yml.template"
    local config_file="/etc/gobackup/gobackup.yml"
    
    # Check if template file exists
    if [ ! -f "${template_file}" ]; then
        log_error "Configuration template not found at ${template_file}"
        exit 1
    fi
    
    # Check if config file already exists (mounted by user)
    if [ -f "${config_file}" ]; then
        log_info "Configuration file already exists at ${config_file}, skipping generation"
        log_info "Using user-provided configuration"
        return 0
    fi
    
    # Use envsubst to substitute environment variables in template
    # Export all variables to make them available to envsubst
    export MSSQL_HOST MSSQL_PORT MSSQL_DATABASE MSSQL_USERNAME MSSQL_PASSWORD MSSQL_TRUST_CERT
    export MINIO_ENDPOINT MINIO_BUCKET MINIO_REGION MINIO_PATH MINIO_ACCESS_KEY MINIO_SECRET_KEY
    export MINIO_TIMEOUT MINIO_MAX_RETRIES BACKUP_CRON
    
    # Substitute variables and write to config file
    envsubst < "${template_file}" > "${config_file}"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to generate configuration file"
        exit 1
    fi
    
    log_info "Configuration file generated successfully at ${config_file}"
    
    # Validate YAML syntax using Python (available in most base images)
    # If Python is not available, skip validation
    if command -v python3 &> /dev/null; then
        python3 -c "import yaml; yaml.safe_load(open('${config_file}'))" 2>/dev/null
        if [ $? -eq 0 ]; then
            log_info "Configuration file YAML syntax is valid"
        else
            log_warning "Could not validate YAML syntax (yaml module not available)"
        fi
    else
        log_warning "Python3 not available, skipping YAML validation"
    fi
}

# Test SQL Server connectivity (optional)
test_sql_connection() {
    if [ "${SKIP_HEALTH_CHECK}" = "true" ]; then
        log_info "Skipping SQL Server health check (SKIP_HEALTH_CHECK=true)"
        return 0
    fi
    
    log_info "Testing SQL Server connectivity"
    
    # Build connection string for sqlpackage
    local sql_host="${MSSQL_HOST}"
    local sql_port="${MSSQL_PORT:-1433}"
    local sql_database="${MSSQL_DATABASE}"
    local sql_username="${MSSQL_USERNAME:-sa}"
    local sql_password="${MSSQL_PASSWORD}"
    
    # Try to connect using sqlpackage with a simple query
    # We'll use the /Action:Script which is less invasive than Export
    local test_output
    test_output=$(sqlpackage /Action:Script \
        /SourceServerName:"${sql_host},${sql_port}" \
        /SourceDatabaseName:"${sql_database}" \
        /SourceUser:"${sql_username}" \
        /SourcePassword:"${sql_password}" \
        /SourceTrustServerCertificate:${MSSQL_TRUST_CERT:-true} \
        /TargetFile:/tmp/test_schema.sql \
        /p:ExtractTarget=SchemaOnly 2>&1 || true)
    
    if [ $? -eq 0 ] && [ -f /tmp/test_schema.sql ]; then
        log_info "SQL Server connection test successful"
        rm -f /tmp/test_schema.sql
        return 0
    else
        log_warning "SQL Server connection test failed"
        log_warning "This is informational only - container will continue"
        log_warning "Error details: ${test_output}"
        return 0
    fi
}

# Test MinIO connectivity (optional)
test_minio_connection() {
    if [ "${SKIP_HEALTH_CHECK}" = "true" ]; then
        log_info "Skipping MinIO health check (SKIP_HEALTH_CHECK=true)"
        return 0
    fi
    
    log_info "Testing MinIO connectivity"
    
    local minio_endpoint="${MINIO_ENDPOINT}"
    local minio_bucket="${MINIO_BUCKET}"
    local minio_access_key="${MINIO_ACCESS_KEY}"
    local minio_secret_key="${MINIO_SECRET_KEY}"
    
    # Try to list bucket using curl (basic connectivity test)
    # Extract hostname and port from endpoint
    local endpoint_host=$(echo "${minio_endpoint}" | sed -E 's|^https?://||' | cut -d: -f1)
    local endpoint_port=$(echo "${minio_endpoint}" | grep -oE ':[0-9]+$' | tr -d ':')
    
    if [ -z "${endpoint_port}" ]; then
        if [[ "${minio_endpoint}" == https://* ]]; then
            endpoint_port="443"
        else
            endpoint_port="80"
        fi
    fi
    
    # Simple connectivity test using curl
    local test_output
    test_output=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "${minio_endpoint}" 2>&1 || true)
    
    if [ "${test_output}" = "403" ] || [ "${test_output}" = "200" ] || [ "${test_output}" = "404" ]; then
        log_info "MinIO connectivity test successful (HTTP ${test_output})"
        return 0
    else
        log_warning "MinIO connectivity test failed (HTTP ${test_output})"
        log_warning "This is informational only - container will continue"
        log_warning "Endpoint: ${minio_endpoint}"
        return 0
    fi
}

# Signal handler for graceful shutdown
cleanup() {
    log_info "Received shutdown signal, cleaning up..."
    
    # Kill any running gobackup processes
    if [ -n "${GOBACKUP_PID}" ]; then
        log_info "Stopping GoBackup process (PID: ${GOBACKUP_PID})"
        kill -TERM "${GOBACKUP_PID}" 2>/dev/null || true
        wait "${GOBACKUP_PID}" 2>/dev/null || true
    fi
    
    log_info "Shutdown complete"
    exit 0
}

# Set up signal handlers for graceful shutdown
trap cleanup SIGTERM SIGINT SIGQUIT

# Execute GoBackup based on run mode
run_gobackup() {
    local run_mode="${RUN_MODE:-daemon}"
    
    log_info "Run mode: ${run_mode}"
    
    case "${run_mode}" in
        once)
            log_info "Executing one-time backup"
            log_info "Running: gobackup perform"
            
            # Execute one-time backup
            gobackup perform
            
            if [ $? -eq 0 ]; then
                log_info "One-time backup completed successfully"
                exit 0
            else
                log_error "One-time backup failed"
                exit 1
            fi
            ;;
            
        daemon)
            log_info "Starting scheduled backup daemon"
            log_info "Running: gobackup run"
            
            # Start GoBackup in daemon mode (scheduled backups)
            gobackup run &
            GOBACKUP_PID=$!
            
            log_info "GoBackup daemon started (PID: ${GOBACKUP_PID})"
            log_info "Container will run continuously and execute backups on schedule"
            
            # Wait for the GoBackup process
            wait "${GOBACKUP_PID}"
            
            # If we reach here, GoBackup exited unexpectedly
            log_error "GoBackup daemon exited unexpectedly"
            exit 1
            ;;
            
        *)
            log_error "Invalid RUN_MODE: ${run_mode}"
            log_error "Valid options are: 'once' or 'daemon'"
            exit 1
            ;;
    esac
}

# Main execution flow
main() {
    log_info "GoBackup SQL Server Backup Container"
    log_info "======================================"
    
    # Step 1: Validate required environment variables
    validate_required_env
    
    # Step 2: Generate configuration file from template
    generate_config
    
    # Step 3: Run optional health checks
    test_sql_connection
    test_minio_connection
    
    # Step 4: Execute GoBackup based on run mode
    run_gobackup
}

# Start main execution
main
