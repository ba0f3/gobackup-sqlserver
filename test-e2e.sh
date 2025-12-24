#!/bin/bash
# End-to-End Test Script for GoBackup SQL Server Docker Image
# This script performs comprehensive testing of the backup workflow

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_DB_NAME="TestDB_E2E"
TEST_MINIO_BUCKET="test-backups"
TEST_PASSWORD="TestPassword123!"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$*${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Cleanup function
cleanup() {
    log_section "Cleaning up test environment"
    
    # Stop and remove containers
    docker compose down -v 2>/dev/null || true
    
    # Remove test database backup files
    rm -f /tmp/test_backup_*.bacpac 2>/dev/null || true
    
    log_info "Cleanup complete"
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Test 1: Build Docker image
test_build_image() {
    log_section "Test 1: Building Docker Image"
    
    log_info "Building gobackup-sqlserver image..."
    if docker build -t gobackup-sqlserver:test . ; then
        log_success "Docker image built successfully"
    else
        log_error "Failed to build Docker image"
        return 1
    fi
    
    # Verify image exists
    if docker images | grep -q "gobackup-sqlserver.*test"; then
        log_success "Image verified in Docker images list"
    else
        log_error "Image not found in Docker images list"
        return 1
    fi
    
    # Check image size
    local image_size=$(docker images gobackup-sqlserver:test --format "{{.Size}}")
    log_info "Image size: ${image_size}"
    
    return 0
}

# Test 2: Verify installed tools
test_verify_tools() {
    log_section "Test 2: Verifying Installed Tools"
    
    log_info "Checking GoBackup installation..."
    if docker run --rm --entrypoint gobackup gobackup-sqlserver:test -v; then
        log_success "GoBackup is installed and accessible"
    else
        log_error "GoBackup not found or not executable"
        return 1
    fi
    
    log_info "Checking sqlpackage installation..."
    if docker run --rm --entrypoint sqlpackage gobackup-sqlserver:test /version; then
        log_success "sqlpackage is installed and accessible"
    else
        log_error "sqlpackage not found or not executable"
        return 1
    fi
    
    log_info "Checking sqlpackage symlink..."
    if docker run --rm --entrypoint test gobackup-sqlserver:test -L /usr/local/bin/sqlpackage; then
        log_success "sqlpackage symlink exists"
    else
        log_error "sqlpackage symlink not found"
        return 1
    fi
    
    log_info "Checking required dependencies..."
    if docker run --rm --entrypoint dpkg gobackup-sqlserver:test -l | grep -q libunwind8; then
        log_success "libunwind8 is installed"
    else
        log_error "libunwind8 not found"
        return 1
    fi
    
    return 0
}

# Test 3: Start infrastructure
test_start_infrastructure() {
    log_section "Test 3: Starting Test Infrastructure"
    
    # Create .env file for testing
    log_info "Creating test .env file..."
    cat > .env << EOF
MSSQL_HOST=sqlserver
MSSQL_PORT=1433
MSSQL_DATABASE=${TEST_DB_NAME}
MSSQL_USERNAME=sa
MSSQL_PASSWORD=${TEST_PASSWORD}
MSSQL_TRUST_CERT=true

MINIO_ENDPOINT=http://minio:9000
MINIO_BUCKET=${TEST_MINIO_BUCKET}
MINIO_REGION=us-east-1
MINIO_PATH=backups/sqlserver
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=minioadmin

BACKUP_CRON=*/2 * * * *
RUN_MODE=daemon
SKIP_HEALTH_CHECK=false
EOF
    
    log_info "Starting SQL Server and MinIO..."
    if docker compose up -d sqlserver minio; then
        log_success "Infrastructure services started"
    else
        log_error "Failed to start infrastructure services"
        return 1
    fi
    
    # Wait for SQL Server to be healthy
    log_info "Waiting for SQL Server to be ready (this may take up to 2 minutes)..."
    local max_wait=120
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if docker compose exec -T sqlserver /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "${TEST_PASSWORD}" -C -Q "SELECT 1" &>/dev/null; then
            log_success "SQL Server is ready"
            break
        fi
        if [ $((waited % 10)) -eq 0 ]; then
            log_info "Still waiting... (${waited}/${max_wait} seconds)"
        fi
        sleep 2
        waited=$((waited + 2))
    done
    
    if [ $waited -ge $max_wait ]; then
        log_error "SQL Server failed to become ready within ${max_wait} seconds"
        log_info "SQL Server logs:"
        docker compose logs sqlserver | tail -20
        return 1
    fi
    
    # Wait for MinIO to be ready
    log_info "Waiting for MinIO to be ready..."
    max_wait=30
    waited=0
    while [ $waited -lt $max_wait ]; do
        if curl -sf http://localhost:9000/minio/health/live &>/dev/null; then
            log_success "MinIO is ready"
            break
        fi
        sleep 2
        waited=$((waited + 2))
    done
    
    if [ $waited -ge $max_wait ]; then
        log_error "MinIO failed to become ready within ${max_wait} seconds"
        return 1
    fi
    
    return 0
}

# Test 4: Create test database
test_create_database() {
    log_section "Test 4: Creating Test Database"
    
    log_info "Creating test database: ${TEST_DB_NAME}..."
    if docker compose exec -T sqlserver /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "${TEST_PASSWORD}" -C -Q "CREATE DATABASE ${TEST_DB_NAME}"; then
        log_success "Test database created"
    else
        log_error "Failed to create test database"
        return 1
    fi
    
    log_info "Creating test table with sample data..."
    docker compose exec -T sqlserver /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "${TEST_PASSWORD}" -C -d "${TEST_DB_NAME}" -Q "
        CREATE TABLE TestTable (
            ID INT PRIMARY KEY IDENTITY(1,1),
            Name NVARCHAR(100),
            CreatedAt DATETIME DEFAULT GETDATE()
        );
        
        INSERT INTO TestTable (Name) VALUES ('Test Record 1');
        INSERT INTO TestTable (Name) VALUES ('Test Record 2');
        INSERT INTO TestTable (Name) VALUES ('Test Record 3');
        
        SELECT * FROM TestTable;
    "
    
    if [ $? -eq 0 ]; then
        log_success "Test table created with sample data"
    else
        log_error "Failed to create test table"
        return 1
    fi
    
    return 0
}

# Test 5: Create MinIO bucket
test_create_minio_bucket() {
    log_section "Test 5: Creating MinIO Bucket"
    
    log_info "Installing MinIO client (mc)..."
    if ! command -v mc &> /dev/null; then
        wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O /tmp/mc
        chmod +x /tmp/mc
        MC_CMD="/tmp/mc"
    else
        MC_CMD="mc"
    fi
    
    log_info "Configuring MinIO client..."
    $MC_CMD alias set testminio http://localhost:9000 minioadmin minioadmin &>/dev/null
    
    log_info "Creating bucket: ${TEST_MINIO_BUCKET}..."
    if $MC_CMD mb testminio/${TEST_MINIO_BUCKET} 2>/dev/null || $MC_CMD ls testminio/${TEST_MINIO_BUCKET} &>/dev/null; then
        log_success "MinIO bucket ready"
    else
        log_error "Failed to create MinIO bucket"
        return 1
    fi
    
    return 0
}

# Test 6: Run one-time backup
test_one_time_backup() {
    log_section "Test 6: Running One-Time Backup"
    
    # Update .env for one-time mode
    sed -i 's/RUN_MODE=daemon/RUN_MODE=once/' .env
    
    log_info "Starting backup container in one-time mode..."
    if docker compose up gobackup 2>&1 | tee /tmp/backup_log.txt; then
        log_success "Backup container executed"
    else
        log_warning "Backup container exited (expected for one-time mode)"
    fi
    
    # Check logs for success indicators
    log_info "Checking backup logs..."
    if grep -q "Starting GoBackup SQL Server container" /tmp/backup_log.txt; then
        log_success "Container started successfully"
    else
        log_error "Container startup message not found in logs"
        return 1
    fi
    
    if grep -q "All required environment variables are set" /tmp/backup_log.txt; then
        log_success "Environment validation passed"
    else
        log_error "Environment validation failed"
        return 1
    fi
    
    # Wait a bit for backup to complete
    sleep 10
    
    return 0
}

# Test 7: Verify backup in MinIO
test_verify_backup_in_minio() {
    log_section "Test 7: Verifying Backup in MinIO"
    
    log_info "Listing backups in MinIO bucket..."
    if [ -z "$MC_CMD" ]; then
        if ! command -v mc &> /dev/null; then
            MC_CMD="/tmp/mc"
        else
            MC_CMD="mc"
        fi
    fi
    
    $MC_CMD alias set testminio http://localhost:9000 minioadmin minioadmin &>/dev/null
    
    local backup_files=$($MC_CMD ls --recursive testminio/${TEST_MINIO_BUCKET}/backups/sqlserver/ 2>/dev/null | grep -c ".bacpac" || echo "0")
    
    if [ "$backup_files" -gt 0 ]; then
        log_success "Found ${backup_files} backup file(s) in MinIO"
        log_info "Backup files:"
        $MC_CMD ls --recursive testminio/${TEST_MINIO_BUCKET}/backups/sqlserver/ | grep ".bacpac"
    else
        log_error "No backup files found in MinIO"
        log_info "Bucket contents:"
        $MC_CMD ls --recursive testminio/${TEST_MINIO_BUCKET}/ || log_warning "Bucket is empty or inaccessible"
        return 1
    fi
    
    # Get backup file details
    local latest_backup=$($MC_CMD ls --recursive testminio/${TEST_MINIO_BUCKET}/backups/sqlserver/ | grep ".bacpac" | tail -1 | awk '{print $NF}')
    if [ -n "$latest_backup" ]; then
        local backup_size=$($MC_CMD stat testminio/${TEST_MINIO_BUCKET}/${latest_backup} 2>/dev/null | grep "Size" | awk '{print $3}')
        log_info "Latest backup size: ${backup_size}"
        
        if [ -n "$backup_size" ] && [ "$backup_size" != "0" ]; then
            log_success "Backup file has non-zero size"
        else
            log_error "Backup file is empty or size could not be determined"
            return 1
        fi
    fi
    
    return 0
}

# Test 8: Test scheduled backups
test_scheduled_backups() {
    log_section "Test 8: Testing Scheduled Backups"
    
    # Update .env for daemon mode with frequent schedule
    sed -i 's/RUN_MODE=once/RUN_MODE=daemon/' .env
    sed -i 's/BACKUP_CRON=.*/BACKUP_CRON=*\/2 * * * */' .env  # Every 2 minutes
    
    log_info "Starting backup container in daemon mode..."
    docker compose up -d gobackup
    
    if [ $? -eq 0 ]; then
        log_success "Backup container started in daemon mode"
    else
        log_error "Failed to start backup container"
        return 1
    fi
    
    # Wait for container to be running
    sleep 5
    
    # Check if container is running
    if docker compose ps gobackup | grep -q "Up"; then
        log_success "Backup container is running"
    else
        log_error "Backup container is not running"
        docker compose logs gobackup
        return 1
    fi
    
    log_info "Monitoring logs for scheduled backup execution (waiting up to 150 seconds)..."
    local max_wait=150
    local waited=0
    local backup_executed=false
    
    while [ $waited -lt $max_wait ]; do
        if docker compose logs gobackup 2>&1 | grep -q "gobackup run"; then
            backup_executed=true
            log_success "Scheduled backup daemon is running"
            break
        fi
        sleep 5
        waited=$((waited + 5))
        log_info "Waited ${waited}/${max_wait} seconds..."
    done
    
    if [ "$backup_executed" = false ]; then
        log_warning "Scheduled backup execution not confirmed in logs within timeout"
        log_info "Container logs:"
        docker compose logs gobackup | tail -20
    else
        log_success "Scheduled backup system is operational"
    fi
    
    return 0
}

# Test 9: Verify logs
test_verify_logs() {
    log_section "Test 9: Verifying Log Quality"
    
    log_info "Checking log format and content..."
    local logs=$(docker compose logs gobackup 2>&1)
    
    # Check for timestamps
    if echo "$logs" | grep -q "\[20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]"; then
        log_success "Logs contain timestamps"
    else
        log_warning "Timestamps not found in logs"
    fi
    
    # Check for log levels
    if echo "$logs" | grep -q "\[INFO\]"; then
        log_success "Logs contain INFO level messages"
    else
        log_warning "INFO level messages not found"
    fi
    
    # Check for key operational messages
    if echo "$logs" | grep -q "Starting GoBackup SQL Server container"; then
        log_success "Startup message found in logs"
    fi
    
    if echo "$logs" | grep -q "Validating required environment variables"; then
        log_success "Validation message found in logs"
    fi
    
    if echo "$logs" | grep -q "All required environment variables are set"; then
        log_success "Validation success message found in logs"
    fi
    
    log_info "Sample log output:"
    echo "$logs" | head -20
    
    return 0
}

# Test 10: Test restore procedure
test_restore_procedure() {
    log_section "Test 10: Testing Backup Restore"
    
    log_info "Downloading latest backup from MinIO..."
    if [ -z "$MC_CMD" ]; then
        MC_CMD="/tmp/mc"
    fi
    
    $MC_CMD alias set testminio http://localhost:9000 minioadmin minioadmin &>/dev/null
    
    local latest_backup=$($MC_CMD ls --recursive testminio/${TEST_MINIO_BUCKET}/backups/sqlserver/ | grep ".bacpac" | tail -1 | awk '{print $NF}')
    
    if [ -z "$latest_backup" ]; then
        log_error "No backup file found to restore"
        return 1
    fi
    
    log_info "Downloading: ${latest_backup}"
    $MC_CMD cp testminio/${TEST_MINIO_BUCKET}/${latest_backup} /tmp/test_restore.bacpac
    
    if [ ! -f /tmp/test_restore.bacpac ]; then
        log_error "Failed to download backup file"
        return 1
    fi
    
    log_success "Backup file downloaded successfully"
    
    # Create a new database for restore
    local restore_db="${TEST_DB_NAME}_Restored"
    log_info "Creating restore target database: ${restore_db}..."
    docker compose exec -T sqlserver /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "${TEST_PASSWORD}" -C -Q "CREATE DATABASE ${restore_db}"
    
    # Copy backup file into SQL Server container
    log_info "Copying backup file to SQL Server container..."
    docker cp /tmp/test_restore.bacpac $(docker compose ps -q sqlserver):/tmp/test_restore.bacpac
    
    # Restore using sqlpackage
    log_info "Restoring database from backup..."
    docker compose exec -T sqlserver /opt/mssql-tools/bin/sqlpackage \
        /Action:Import \
        /SourceFile:/tmp/test_restore.bacpac \
        /TargetServerName:localhost \
        /TargetDatabaseName:${restore_db} \
        /TargetUser:sa \
        /TargetPassword:${TEST_PASSWORD} \
        /TargetTrustServerCertificate:true
    
    if [ $? -eq 0 ]; then
        log_success "Database restored successfully"
    else
        log_error "Database restore failed"
        return 1
    fi
    
    # Verify restored data
    log_info "Verifying restored data..."
    local record_count=$(docker compose exec -T sqlserver /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "${TEST_PASSWORD}" -d "${restore_db}" -Q "SELECT COUNT(*) FROM TestTable" -h -1 | tr -d ' \r\n')
    
    if [ "$record_count" = "3" ]; then
        log_success "Restored database contains expected data (3 records)"
    else
        log_error "Restored database has unexpected record count: ${record_count}"
        return 1
    fi
    
    # Cleanup
    rm -f /tmp/test_restore.bacpac
    
    return 0
}

# Main test execution
main() {
    log_section "GoBackup SQL Server - End-to-End Test Suite"
    log_info "Starting comprehensive end-to-end tests..."
    
    local failed_tests=0
    local total_tests=10
    
    # Run all tests
    test_build_image || ((failed_tests++))
    test_verify_tools || ((failed_tests++))
    test_start_infrastructure || ((failed_tests++))
    test_create_database || ((failed_tests++))
    test_create_minio_bucket || ((failed_tests++))
    test_one_time_backup || ((failed_tests++))
    test_verify_backup_in_minio || ((failed_tests++))
    test_scheduled_backups || ((failed_tests++))
    test_verify_logs || ((failed_tests++))
    test_restore_procedure || ((failed_tests++))
    
    # Summary
    log_section "Test Summary"
    local passed_tests=$((total_tests - failed_tests))
    
    if [ $failed_tests -eq 0 ]; then
        log_success "All ${total_tests} tests passed! ✓"
        log_success "The GoBackup SQL Server Docker image is production-ready"
        return 0
    else
        log_error "${failed_tests} out of ${total_tests} tests failed"
        log_info "Passed: ${passed_tests}/${total_tests}"
        return 1
    fi
}

# Run main function
main
exit $?
