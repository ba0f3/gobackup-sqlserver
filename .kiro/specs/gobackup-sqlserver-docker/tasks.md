# Implementation Plan: GoBackup SQL Server Docker Image

## Overview

This implementation plan creates a Docker image combining GoBackup and Microsoft sqlpackage for automated SQL Server backups to MinIO. The implementation focuses on creating the Dockerfile, entrypoint script, configuration templates, and supporting documentation. Since this is primarily an infrastructure project, testing will focus on integration tests rather than property-based tests.

## Tasks

- [x] 1. Create project structure and base files
  - Create directory structure for the project
  - Create README.md with project overview and usage instructions
  - Create .dockerignore file to exclude unnecessary files from build context
  - Create example .env file with all required environment variables
  - _Requirements: 6.5, 8.4_

- [x] 2. Implement Dockerfile
  - [x] 2.1 Create Dockerfile with Ubuntu base image
    - Use ubuntu:22.04 as base image
    - Set up working directory and environment variables
    - _Requirements: 1.1_
  
  - [x] 2.2 Add sqlpackage installation steps
    - Install system dependencies (libunwind8, wget, unzip, ca-certificates)
    - Download sqlpackage from Microsoft's official URL
    - Extract to /usr/local/sqlpackage
    - Set executable permissions
    - Create symlink at /usr/local/bin/sqlpackage
    - Verify installation with version check
    - _Requirements: 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 2.4, 2.5_
  
  - [x] 2.3 Add GoBackup installation
    - Download GoBackup binary from GitHub releases (latest stable version)
    - Install to /usr/local/bin/gobackup
    - Set executable permissions
    - Verify installation
    - _Requirements: 1.2_
  
  - [x] 2.4 Configure container runtime settings
    - Create /etc/gobackup directory for configuration
    - Create /tmp/gobackup directory for temporary files
    - Clean up installation artifacts to reduce image size
    - Set appropriate file permissions
    - _Requirements: 1.6_

- [x] 3. Create GoBackup configuration template
  - Create gobackup.yml.template with environment variable placeholders
  - Include MSSQL database configuration section
  - Include MinIO storage configuration section
  - Include schedule configuration with cron support
  - Add comments explaining each configuration option
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 4.1, 4.2, 4.3, 4.4, 5.1, 6.1, 6.2_

- [x] 4. Implement entrypoint script
  - [x] 4.1 Create entrypoint.sh with basic structure
    - Add shebang and set error handling (set -e)
    - Define logging functions (log_info, log_error, log_warning)
    - _Requirements: 7.5_
  
  - [x] 4.2 Implement environment variable validation
    - Check for required MSSQL variables (host, database, password)
    - Check for required MinIO variables (endpoint, bucket, access_key, secret_key)
    - Log clear error messages for missing variables
    - Exit with code 1 if validation fails
    - _Requirements: 6.3_
  
  - [x] 4.3 Implement configuration file generation
    - Read gobackup.yml.template
    - Substitute environment variables using envsubst or similar
    - Write final configuration to /etc/gobackup/gobackup.yml
    - Validate YAML syntax
    - _Requirements: 6.2, 6.4_
  
  - [x] 4.4 Add optional health checks
    - Implement SQL Server connection test (skippable via SKIP_HEALTH_CHECK)
    - Implement MinIO connectivity test (skippable via SKIP_HEALTH_CHECK)
    - Log results without failing if health checks are informational
    - _Requirements: 8.5_
  
  - [x] 4.5 Implement run mode logic
    - Support RUN_MODE=once for one-time backup execution
    - Support RUN_MODE=daemon for scheduled backups (default)
    - Execute appropriate gobackup command based on mode
    - Add proper signal handling for graceful shutdown
    - _Requirements: 5.1, 8.1_

- [x] 5. Add Dockerfile entrypoint and CMD
  - Copy entrypoint.sh to /entrypoint.sh in image
  - Set executable permissions on entrypoint script
  - Define ENTRYPOINT ["/entrypoint.sh"]
  - Add health check using Docker HEALTHCHECK instruction
  - _Requirements: 8.5_

- [x] 6. Create docker-compose.yml example
  - Create docker-compose.yml with gobackup, SQL Server, and MinIO services
  - Configure environment variables and volume mounts
  - Add depends_on relationships
  - Include comments explaining each service
  - _Requirements: 8.1, 8.2, 8.3_

- [x] 7. Create example configuration files
  - Create example gobackup.yml with inline comments
  - Create example .env file with all required variables
  - Create example cron schedules in documentation
  - _Requirements: 6.5_

- [x] 8. Checkpoint - Build and test image locally
  - Build Docker image locally
  - Verify image builds without errors
  - Check image size is reasonable
  - Ensure all tests pass, ask the user if questions arise

- [ ]* 9. Create integration test suite
  - [ ]* 9.1 Create test infrastructure setup script
    - Script to start SQL Server and MinIO containers for testing
    - Script to create test database and MinIO bucket
    - Script to populate test data
    - _Requirements: 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 2.4, 2.5_
  
  - [ ]* 9.2 Write Docker image build verification tests
    - Test that gobackup binary exists and is executable
    - Test that sqlpackage exists at correct path
    - Test that symlink exists
    - Test that dependencies are installed
    - _Requirements: 1.2, 1.3, 1.4, 1.5, 2.4, 2.5_
  
  - [ ]* 9.3 Write configuration and environment variable tests
    - Test configuration file mounting
    - Test environment variable substitution
    - Test required variable validation
    - _Requirements: 3.1, 6.1, 6.2, 6.3, 6.4, 8.2, 8.4_
  
  - [ ]* 9.4 Write backup execution tests
    - Test SQL Server backup creates .bacpac file
    - Test MinIO upload succeeds
    - Test backup file appears in MinIO at correct path
    - _Requirements: 3.2, 3.3, 3.4, 4.2, 4.3, 4.4, 5.2, 5.3_
  
  - [ ]* 9.5 Write error handling tests
    - Test upload failure handling (invalid credentials)
    - Test sqlpackage failure handling (invalid database)
    - Test local backup retention on upload failure
    - _Requirements: 4.5, 5.5, 7.3, 7.4_
  
  - [ ]* 9.6 Write logging verification tests
    - Test logs contain timestamps and operation details
    - Test logs contain success information (completion time, file size)
    - Test logs contain error details on failure
    - Test logs output to stdout
    - _Requirements: 5.4, 7.1, 7.2, 7.5_
  
  - [ ]* 9.7 Write scheduling tests
    - Test cron schedule configuration
    - Test scheduled backup execution
    - Test daemon mode keeps container running
    - _Requirements: 3.5, 5.1, 8.1_
  
  - [ ]* 9.8 Write volume mount tests
    - Test configuration file volume mount
    - Test temporary storage volume mount
    - _Requirements: 8.2, 8.3_
  
  - [ ]* 9.9 Write health check tests
    - Test Docker health check reports healthy status
    - Test health check detects failures
    - _Requirements: 8.5_

- [x] 10. Create comprehensive documentation
  - [x] 10.1 Write README.md
    - Add project description and features
    - Add prerequisites and requirements
    - Add quick start guide
    - Add configuration reference for all environment variables
    - Add usage examples (one-time backup, scheduled backups)
    - Add troubleshooting section
  
  - [x] 10.2 Write CONFIGURATION.md
    - Document all GoBackup configuration options
    - Document all environment variables with defaults
    - Provide configuration examples for common scenarios
    - Document MinIO bucket setup requirements
    - Document SQL Server permissions requirements
  
  - [x] 10.3 Create deployment guide
    - Document Docker deployment steps
    - Document docker-compose deployment
    - Document Kubernetes deployment (optional)
    - Document backup verification procedures
    - Document restore procedures using sqlpackage

- [x] 11. Final checkpoint - End-to-end testing
  - Run complete backup workflow with real SQL Server and MinIO
  - Verify scheduled backups execute correctly over time
  - Verify logs are clear and actionable
  - Test restore procedure to validate backup integrity
  - Ensure all tests pass, ask the user if questions arise

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- The entrypoint script will be implemented in Bash as it's the standard for Docker entrypoints
- Integration tests are more appropriate than property-based tests for this infrastructure project
- Each task references specific requirements for traceability
- Focus on creating a production-ready, well-documented Docker image
- Image size optimization is important but secondary to functionality
