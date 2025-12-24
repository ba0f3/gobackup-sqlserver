# GoBackup SQL Server Configuration Guide

This document provides comprehensive configuration information for the GoBackup SQL Server Docker image, including all environment variables, GoBackup configuration options, and setup requirements for SQL Server and MinIO.

## Table of Contents

- [Environment Variables](#environment-variables)
- [GoBackup Configuration File](#gobackup-configuration-file)
- [SQL Server Setup](#sql-server-setup)
- [MinIO Setup](#minio-setup)
- [Configuration Examples](#configuration-examples)
- [Advanced Configuration](#advanced-configuration)

## Environment Variables

### Required Environment Variables

These variables MUST be set for the container to function:

#### SQL Server Connection

| Variable | Description | Example |
|----------|-------------|---------|
| `MSSQL_HOST` | SQL Server hostname or IP address | `sqlserver.example.com` |
| `MSSQL_DATABASE` | Database name to backup | `myapp_production` |
| `MSSQL_PASSWORD` | SQL Server authentication password | `YourStrongPassword123!` |

#### MinIO Storage

| Variable | Description | Example |
|----------|-------------|---------|
| `MINIO_ENDPOINT` | MinIO endpoint URL (include protocol) | `http://minio:9000` |
| `MINIO_BUCKET` | MinIO bucket name for backups | `database-backups` |
| `MINIO_ACCESS_KEY` | MinIO access key ID | `your-access-key` |
| `MINIO_SECRET_KEY` | MinIO secret access key | `your-secret-key` |

### Optional Environment Variables

These variables have sensible defaults but can be customized:

#### SQL Server Options

| Variable | Default | Description |
|----------|---------|-------------|
| `MSSQL_PORT` | `1433` | SQL Server port number |
| `MSSQL_USERNAME` | `sa` | SQL Server authentication username |
| `MSSQL_TRUST_CERT` | `true` | Trust server certificate for TLS connections |

**MSSQL_TRUST_CERT Details:**
- Set to `true` for self-signed certificates or non-production environments
- Set to `false` when using properly signed SSL certificates
- Required for SQL Server instances with TLS/SSL enabled

#### MinIO Options

| Variable | Default | Description |
|----------|---------|-------------|
| `MINIO_REGION` | `us-east-1` | MinIO region (can be any value for MinIO) |
| `MINIO_PATH` | `backups/sqlserver` | Path prefix within the bucket |
| `MINIO_TIMEOUT` | `300` | Upload timeout in seconds (5 minutes) |
| `MINIO_MAX_RETRIES` | `3` | Maximum number of upload retry attempts |

**MINIO_PATH Details:**
- Backups are stored at: `{bucket}/{path}/{model_name}/{timestamp}/`
- Example: `backups/backups/sqlserver/sqlserver_backup/2024-12-24T02-00-00/`
- Use different paths to organize backups by environment or application

**MINIO_TIMEOUT Recommendations:**
- Small databases (< 1GB): 300 seconds (default)
- Medium databases (1-10GB): 600-1800 seconds
- Large databases (> 10GB): 3600+ seconds
- Adjust based on network speed and database size

#### Backup Schedule

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKUP_CRON` | `0 2 * * *` | Cron expression for backup schedule |
| `RUN_MODE` | `daemon` | Run mode: `daemon` or `once` |
| `SKIP_HEALTH_CHECK` | `false` | Skip startup health checks |

**BACKUP_CRON Format:**
```
"minute hour day month weekday"
```

Fields:
- `minute`: 0-59
- `hour`: 0-23 (0 = midnight, 12 = noon)
- `day`: 1-31
- `month`: 1-12
- `weekday`: 0-7 (0 and 7 = Sunday)

Special characters:
- `*` = any value
- `*/n` = every n units
- `,` = list of values
- `-` = range of values

**RUN_MODE Options:**
- `daemon`: Run continuously with scheduled backups (default)
- `once`: Execute a single backup and exit

**SKIP_HEALTH_CHECK Usage:**
- Set to `true` to skip SQL Server and MinIO connectivity tests at startup
- Useful for faster startup or when health checks fail incorrectly
- Not recommended for production use

## GoBackup Configuration File

The container uses a configuration template at `/app/gobackup.yml.template` that is processed with environment variable substitution. You can also mount your own configuration file at `/etc/gobackup/gobackup.yml`.

### Configuration File Structure

```yaml
models:
  model_name:
    description: "Description of backup job"
    schedule:
      cron: "cron expression"
    databases:
      db_identifier:
        type: mssql
        host: "hostname"
        port: 1433
        database: "database_name"
        username: "username"
        password: "password"
        trustServerCertificate: true
    storages:
      storage_identifier:
        type: minio
        bucket: "bucket_name"
        endpoint: "http://minio:9000"
        region: "us-east-1"
        path: "backup/path"
        access_key_id: "access_key"
        secret_access_key: "secret_key"
        timeout: 300
        max_retries: 3
```

### Database Configuration Options

#### MSSQL Database Type

```yaml
databases:
  main_db:
    type: mssql                          # Required: Must be "mssql"
    host: "${MSSQL_HOST}"                # Required: SQL Server hostname
    port: ${MSSQL_PORT:-1433}            # Optional: Port (default: 1433)
    database: "${MSSQL_DATABASE}"        # Required: Database name
    username: "${MSSQL_USERNAME:-sa}"    # Optional: Username (default: sa)
    password: "${MSSQL_PASSWORD}"        # Required: Password
    trustServerCertificate: ${MSSQL_TRUST_CERT:-true}  # Optional: Trust cert
    args: "/p:CompressionOption=Maximum" # Optional: Additional sqlpackage args
```

**Additional sqlpackage Arguments:**

The `args` field allows passing additional arguments to sqlpackage. Common options:

- `/p:CompressionOption=Maximum` - Maximum compression for .bacpac files
- `/p:VerifyExtraction=true` - Verify backup integrity after creation
- `/p:Storage=File` - Use file-based storage (default)
- `/p:CommandTimeout=3600` - Set command timeout in seconds

Example with multiple arguments:
```yaml
args: "/p:CompressionOption=Maximum /p:VerifyExtraction=true /p:CommandTimeout=3600"
```

### Storage Configuration Options

#### MinIO Storage Type

```yaml
storages:
  minio_storage:
    type: minio                                    # Required: Must be "minio"
    bucket: "${MINIO_BUCKET}"                      # Required: Bucket name
    endpoint: "${MINIO_ENDPOINT}"                  # Required: MinIO endpoint URL
    region: "${MINIO_REGION:-us-east-1}"           # Optional: Region
    path: "${MINIO_PATH:-backups/sqlserver}"       # Optional: Path prefix
    access_key_id: "${MINIO_ACCESS_KEY}"           # Required: Access key
    secret_access_key: "${MINIO_SECRET_KEY}"       # Required: Secret key
    timeout: ${MINIO_TIMEOUT:-300}                 # Optional: Timeout (seconds)
    max_retries: ${MINIO_MAX_RETRIES:-3}           # Optional: Retry attempts
    force_path_style: true                         # Optional: Force path-style URLs
```

**force_path_style:**
- Set to `true` for MinIO and some S3-compatible services
- Uses path-style URLs: `http://endpoint/bucket/key`
- Default (false) uses virtual-hosted style: `http://bucket.endpoint/key`

### Global Configuration Options

```yaml
# Working directory for temporary backup files
workdir: "/tmp/gobackup"

# Logging level: debug, info, warn, error
log_level: "info"

# Keep local backup files if upload fails
keep_local_on_failure: true
```

### Notification Configuration

GoBackup supports notifications for backup completion or failure:

#### Slack Notifications

```yaml
notifiers:
  slack:
    webhook_url: "${SLACK_WEBHOOK_URL}"
    channel: "#backups"
    username: "GoBackup"
```

#### Email Notifications

```yaml
notifiers:
  email:
    smtp_host: "${SMTP_HOST}"
    smtp_port: ${SMTP_PORT:-587}
    smtp_user: "${SMTP_USER}"
    smtp_password: "${SMTP_PASSWORD}"
    from: "${EMAIL_FROM}"
    to: "${EMAIL_TO}"
```

### Compression Configuration

```yaml
compressor:
  type: tgz    # Options: tgz, zip
  level: 9     # Compression level (1-9, higher = better compression)
```

**Note:** .bacpac files are already compressed, so additional compression may not provide significant benefits.

### Encryption Configuration

```yaml
encryptor:
  type: openssl
  password: "${ENCRYPTION_PASSWORD}"
  salt: true
  base64: true
```

### Retention Policy Configuration

```yaml
archive:
  keep_days: 30      # Keep daily backups for 30 days
  keep_weeks: 8      # Keep weekly backups for 8 weeks
  keep_months: 12    # Keep monthly backups for 12 months
```

## SQL Server Setup

### Required Permissions

The SQL Server user must have appropriate permissions to perform backups. The minimum required permissions are:

#### Option 1: db_backupoperator Role (Recommended)

```sql
USE [master];
GO

-- Create a dedicated backup user
CREATE LOGIN [gobackup_user] WITH PASSWORD = 'StrongPassword123!';
GO

-- Grant access to the database
USE [your_database];
GO
CREATE USER [gobackup_user] FOR LOGIN [gobackup_user];
GO

-- Add to db_backupoperator role
ALTER ROLE [db_backupoperator] ADD MEMBER [gobackup_user];
GO

-- Grant CONNECT permission
GRANT CONNECT TO [gobackup_user];
GO
```

#### Option 2: db_owner Role (More Permissive)

```sql
USE [your_database];
GO

CREATE USER [gobackup_user] FOR LOGIN [gobackup_user];
GO

ALTER ROLE [db_owner] ADD MEMBER [gobackup_user];
GO
```

#### Option 3: Specific Permissions (Minimal)

```sql
USE [your_database];
GO

CREATE USER [gobackup_user] FOR LOGIN [gobackup_user];
GO

-- Grant necessary permissions for sqlpackage
GRANT VIEW DEFINITION TO [gobackup_user];
GRANT VIEW DATABASE STATE TO [gobackup_user];
GRANT SELECT TO [gobackup_user];
GO
```

### SQL Server Authentication Mode

Ensure SQL Server is configured for SQL Server and Windows Authentication mode (Mixed Mode):

1. Open SQL Server Management Studio (SSMS)
2. Right-click the server instance → Properties
3. Select "Security" page
4. Under "Server authentication", select "SQL Server and Windows Authentication mode"
5. Restart SQL Server service

### Network Configuration

#### Firewall Rules

Ensure SQL Server port (default 1433) is accessible:

**Windows Firewall:**
```powershell
New-NetFirewallRule -DisplayName "SQL Server" -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow
```

**Linux (iptables):**
```bash
sudo iptables -A INPUT -p tcp --dport 1433 -j ACCEPT
```

#### SQL Server Network Configuration

Enable TCP/IP protocol:

1. Open SQL Server Configuration Manager
2. Expand "SQL Server Network Configuration"
3. Select "Protocols for [Instance Name]"
4. Right-click "TCP/IP" → Enable
5. Restart SQL Server service

### TLS/SSL Configuration

If using TLS/SSL with self-signed certificates, set `MSSQL_TRUST_CERT=true`.

For production with proper certificates:
1. Install valid SSL certificate on SQL Server
2. Configure SQL Server to use the certificate
3. Set `MSSQL_TRUST_CERT=false` in container configuration

## MinIO Setup

### Creating a Bucket

#### Using MinIO Console (Web UI)

1. Access MinIO Console at `http://your-minio:9001`
2. Log in with root credentials
3. Navigate to "Buckets" → "Create Bucket"
4. Enter bucket name (e.g., `database-backups`)
5. Click "Create Bucket"

#### Using MinIO Client (mc)

```bash
# Configure mc with your MinIO instance
mc alias set myminio http://your-minio:9000 minioadmin minioadmin

# Create bucket
mc mb myminio/database-backups

# Verify bucket was created
mc ls myminio
```

### Creating Access Keys

#### Using MinIO Console

1. Navigate to "Identity" → "Users"
2. Click "Create User"
3. Enter access key and secret key
4. Assign policies (e.g., `readwrite` for backup bucket)
5. Click "Save"

#### Using MinIO Client

```bash
# Create a new user
mc admin user add myminio gobackup-user StrongPassword123

# Create a policy for the backup bucket
cat > backup-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::database-backups/*",
        "arn:aws:s3:::database-backups"
      ]
    }
  ]
}
EOF

# Add the policy
mc admin policy add myminio backup-policy backup-policy.json

# Assign policy to user
mc admin policy set myminio backup-policy user=gobackup-user
```

### Bucket Policies

For production, configure appropriate bucket policies to restrict access:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": ["arn:aws:iam::*:user/gobackup-user"]
      },
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": ["arn:aws:s3:::database-backups/*"]
    },
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": ["arn:aws:iam::*:user/gobackup-user"]
      },
      "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::database-backups"]
    }
  ]
}
```

### Lifecycle Policies

Configure lifecycle policies to automatically delete old backups:

```bash
# Create lifecycle policy
cat > lifecycle.json <<EOF
{
  "Rules": [
    {
      "ID": "DeleteOldBackups",
      "Status": "Enabled",
      "Expiration": {
        "Days": 30
      },
      "Filter": {
        "Prefix": "backups/sqlserver/"
      }
    }
  ]
}
EOF

# Apply lifecycle policy
mc ilm import myminio/database-backups < lifecycle.json
```

### Network Configuration

Ensure MinIO is accessible from the backup container:

- MinIO API port (default: 9000) must be accessible
- If using Docker networks, services should be on the same network
- For external MinIO, ensure firewall rules allow connections

## Configuration Examples

### Example 1: Single Database, Daily Backups

**.env file:**
```bash
MSSQL_HOST=sqlserver.example.com
MSSQL_DATABASE=production_db
MSSQL_PASSWORD=SecurePassword123!
MINIO_ENDPOINT=http://minio:9000
MINIO_BUCKET=prod-backups
MINIO_ACCESS_KEY=prod-backup-user
MINIO_SECRET_KEY=SecureKey123!
BACKUP_CRON=0 2 * * *
```

### Example 2: Multiple Databases with Custom Configuration

**gobackup.yml:**
```yaml
models:
  production_db:
    description: "Production database backup"
    schedule:
      cron: "0 2 * * *"
    databases:
      prod:
        type: mssql
        host: "sqlserver-prod"
        database: "production"
        username: "backup_user"
        password: "${PROD_DB_PASSWORD}"
    storages:
      minio_prod:
        type: minio
        bucket: "prod-backups"
        endpoint: "http://minio:9000"
        path: "databases/production"
        access_key_id: "${MINIO_ACCESS_KEY}"
        secret_access_key: "${MINIO_SECRET_KEY}"

  staging_db:
    description: "Staging database backup"
    schedule:
      cron: "0 4 * * *"
    databases:
      staging:
        type: mssql
        host: "sqlserver-staging"
        database: "staging"
        username: "backup_user"
        password: "${STAGING_DB_PASSWORD}"
    storages:
      minio_staging:
        type: minio
        bucket: "staging-backups"
        endpoint: "http://minio:9000"
        path: "databases/staging"
        access_key_id: "${MINIO_ACCESS_KEY}"
        secret_access_key: "${MINIO_SECRET_KEY}"
```

### Example 3: High-Frequency Backups with Notifications

**.env file:**
```bash
MSSQL_HOST=sqlserver
MSSQL_DATABASE=critical_db
MSSQL_PASSWORD=SecurePassword123!
MINIO_ENDPOINT=http://minio:9000
MINIO_BUCKET=critical-backups
MINIO_ACCESS_KEY=backup-user
MINIO_SECRET_KEY=SecureKey123!
BACKUP_CRON=0 */4 * * *
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

**gobackup.yml:**
```yaml
models:
  critical_db:
    description: "Critical database - 4-hour backups"
    schedule:
      cron: "0 */4 * * *"
    databases:
      main:
        type: mssql
        host: "${MSSQL_HOST}"
        database: "${MSSQL_DATABASE}"
        username: "sa"
        password: "${MSSQL_PASSWORD}"
        args: "/p:CompressionOption=Maximum /p:VerifyExtraction=true"
    storages:
      minio:
        type: minio
        bucket: "${MINIO_BUCKET}"
        endpoint: "${MINIO_ENDPOINT}"
        access_key_id: "${MINIO_ACCESS_KEY}"
        secret_access_key: "${MINIO_SECRET_KEY}"
        timeout: 600
        max_retries: 5

notifiers:
  slack:
    webhook_url: "${SLACK_WEBHOOK_URL}"

archive:
  keep_days: 7
  keep_weeks: 4
  keep_months: 6
```

### Example 4: Encrypted Backups with Retention

**gobackup.yml:**
```yaml
models:
  encrypted_backup:
    description: "Encrypted database backup with retention"
    schedule:
      cron: "0 3 * * *"
    databases:
      main:
        type: mssql
        host: "${MSSQL_HOST}"
        database: "${MSSQL_DATABASE}"
        username: "${MSSQL_USERNAME}"
        password: "${MSSQL_PASSWORD}"
    storages:
      minio:
        type: minio
        bucket: "${MINIO_BUCKET}"
        endpoint: "${MINIO_ENDPOINT}"
        path: "encrypted-backups"
        access_key_id: "${MINIO_ACCESS_KEY}"
        secret_access_key: "${MINIO_SECRET_KEY}"

encryptor:
  type: openssl
  password: "${ENCRYPTION_PASSWORD}"
  salt: true
  base64: true

archive:
  keep_days: 30
  keep_weeks: 8
  keep_months: 12
```

## Advanced Configuration

### Custom Entrypoint Script

You can extend the entrypoint script by mounting a custom script:

```bash
docker run -v ./custom-entrypoint.sh:/custom-entrypoint.sh \
  --entrypoint /custom-entrypoint.sh \
  gobackup-sqlserver:latest
```

### Volume Mounts for Configuration

Mount custom configuration files:

```yaml
volumes:
  - ./gobackup.yml:/etc/gobackup/gobackup.yml:ro
  - ./custom-scripts:/scripts:ro
  - backup-temp:/tmp/gobackup
```

### Resource Limits

Configure resource limits in docker-compose.yml:

```yaml
deploy:
  resources:
    limits:
      cpus: '2.0'
      memory: 2G
    reservations:
      cpus: '1.0'
      memory: 1G
```

### Logging Configuration

Configure logging driver:

```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```

### Health Check Customization

Customize health check parameters:

```dockerfile
HEALTHCHECK --interval=60s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep -f "gobackup" > /dev/null || exit 1
```

### Environment-Specific Configurations

Use different .env files for different environments:

```bash
# Development
docker-compose --env-file .env.dev up

# Staging
docker-compose --env-file .env.staging up

# Production
docker-compose --env-file .env.prod up
```

## Troubleshooting Configuration Issues

### Validating Configuration

Test configuration with a one-time backup:

```bash
docker run --rm \
  -e RUN_MODE=once \
  -e MSSQL_HOST=... \
  -e MSSQL_DATABASE=... \
  -e MSSQL_PASSWORD=... \
  -e MINIO_ENDPOINT=... \
  -e MINIO_BUCKET=... \
  -e MINIO_ACCESS_KEY=... \
  -e MINIO_SECRET_KEY=... \
  gobackup-sqlserver:latest
```

### Common Configuration Errors

**Error: Missing required environment variable**
- Solution: Ensure all required variables are set in .env file or docker-compose.yml

**Error: SQL Server connection failed**
- Check MSSQL_HOST, MSSQL_PORT, and network connectivity
- Verify SQL Server authentication mode and user permissions
- Check firewall rules

**Error: MinIO upload failed**
- Verify MINIO_ENDPOINT is correct and accessible
- Check MINIO_ACCESS_KEY and MINIO_SECRET_KEY are valid
- Ensure MinIO bucket exists
- Verify network connectivity

**Error: Invalid cron expression**
- Validate cron syntax using online tools
- Ensure proper quoting in environment variables

### Debugging Tips

Enable debug logging:

```bash
# In .env file
LOG_LEVEL=debug

# Or in gobackup.yml
log_level: "debug"
```

Check container logs:

```bash
docker logs -f gobackup-sqlserver
```

Test SQL Server connectivity:

```bash
docker exec gobackup-sqlserver sqlpackage /Action:Script \
  /SourceServerName:${MSSQL_HOST} \
  /SourceDatabaseName:${MSSQL_DATABASE} \
  /SourceUser:${MSSQL_USERNAME} \
  /SourcePassword:${MSSQL_PASSWORD} \
  /TargetFile:/tmp/test.sql
```

Test MinIO connectivity:

```bash
docker exec gobackup-sqlserver curl -v ${MINIO_ENDPOINT}
```

## Security Best Practices

1. **Never commit credentials to version control**
   - Use .env files and add them to .gitignore
   - Use Docker secrets or vault solutions for production

2. **Use strong passwords**
   - SQL Server passwords should meet complexity requirements
   - MinIO credentials should be strong and unique

3. **Limit permissions**
   - Use dedicated SQL Server user with minimal required permissions
   - Use dedicated MinIO user with access only to backup bucket

4. **Enable TLS/SSL**
   - Use HTTPS for MinIO endpoint in production
   - Configure proper SSL certificates for SQL Server

5. **Encrypt backups**
   - Use GoBackup's encryption feature for sensitive data
   - Consider encryption at rest in MinIO

6. **Secure the .env file**
   ```bash
   chmod 600 .env
   ```

7. **Regular security updates**
   - Keep Docker image updated
   - Update SQL Server and MinIO regularly

8. **Monitor and audit**
   - Enable logging and monitoring
   - Review backup logs regularly
   - Set up alerts for backup failures

## Additional Resources

- [GoBackup Documentation](https://gobackup.github.io/)
- [Microsoft sqlpackage Documentation](https://docs.microsoft.com/en-us/sql/tools/sqlpackage/)
- [MinIO Documentation](https://min.io/docs/minio/linux/index.html)
- [Docker Documentation](https://docs.docker.com/)
- [Cron Expression Generator](https://crontab.guru/)

