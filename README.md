# GoBackup SQL Server Docker Image

A Docker image combining [GoBackup](https://github.com/gobackup/gobackup) and Microsoft's sqlpackage tool for automated SQL Server database backups to MinIO object storage.

## Features

- **Automated SQL Server Backups**: Uses Microsoft sqlpackage to create .bacpac database exports
- **MinIO Integration**: Automatically uploads backups to S3-compatible MinIO storage
- **Flexible Scheduling**: Support for cron-based scheduled backups or one-time execution
- **Environment-Based Configuration**: Easy configuration via environment variables
- **Production Ready**: Comprehensive logging, error handling, and health checks

## Prerequisites

- Docker or Docker Compose
- SQL Server instance (2017 or later)
- MinIO or S3-compatible object storage
- Network connectivity between container and SQL Server/MinIO

## Quick Start

### Using Docker Run

```bash
docker run -d \
  --name gobackup-sqlserver \
  -e MSSQL_HOST=your-sqlserver-host \
  -e MSSQL_DATABASE=your-database \
  -e MSSQL_PASSWORD=your-password \
  -e MINIO_ENDPOINT=http://your-minio:9000 \
  -e MINIO_BUCKET=backups \
  -e MINIO_ACCESS_KEY=your-access-key \
  -e MINIO_SECRET_KEY=your-secret-key \
  -e BACKUP_CRON="0 2 * * *" \
  gobackup-sqlserver:latest
```

### Using Docker Compose

1. Copy the example environment file:
```bash
cp .env.example .env
```

2. Edit `.env` with your configuration

3. Start the services:
```bash
docker-compose up -d
```

## Configuration

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `MSSQL_HOST` | SQL Server hostname or IP | `sqlserver.example.com` |
| `MSSQL_DATABASE` | Database name to backup | `myapp_production` |
| `MSSQL_PASSWORD` | SQL Server password | `YourStrongPassword123` |
| `MINIO_ENDPOINT` | MinIO endpoint URL | `http://minio:9000` |
| `MINIO_BUCKET` | MinIO bucket name | `backups` |
| `MINIO_ACCESS_KEY` | MinIO access key | `minioadmin` |
| `MINIO_SECRET_KEY` | MinIO secret key | `minioadmin` |

### Optional Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MSSQL_PORT` | SQL Server port | `1433` |
| `MSSQL_USERNAME` | SQL Server username | `sa` |
| `MSSQL_TRUST_CERT` | Trust server certificate | `true` |
| `MINIO_REGION` | MinIO region | `us-east-1` |
| `MINIO_PATH` | Backup path prefix in bucket | `backups/sqlserver` |
| `BACKUP_CRON` | Cron schedule for backups | `0 2 * * *` (2 AM daily) |
| `RUN_MODE` | Run mode: `daemon` or `once` | `daemon` |
| `SKIP_HEALTH_CHECK` | Skip startup health checks | `false` |

## Usage Examples

### One-Time Backup

Run a single backup and exit:

```bash
docker run --rm \
  -e RUN_MODE=once \
  -e MSSQL_HOST=sqlserver \
  -e MSSQL_DATABASE=mydb \
  -e MSSQL_PASSWORD=password \
  -e MINIO_ENDPOINT=http://minio:9000 \
  -e MINIO_BUCKET=backups \
  -e MINIO_ACCESS_KEY=minioadmin \
  -e MINIO_SECRET_KEY=minioadmin \
  gobackup-sqlserver:latest
```

### Scheduled Backups

Run backups on a schedule (default: 2 AM daily):

```bash
docker run -d \
  --name gobackup-sqlserver \
  -e RUN_MODE=daemon \
  -e BACKUP_CRON="0 2 * * *" \
  -e MSSQL_HOST=sqlserver \
  -e MSSQL_DATABASE=mydb \
  -e MSSQL_PASSWORD=password \
  -e MINIO_ENDPOINT=http://minio:9000 \
  -e MINIO_BUCKET=backups \
  -e MINIO_ACCESS_KEY=minioadmin \
  -e MINIO_SECRET_KEY=minioadmin \
  gobackup-sqlserver:latest
```

### Custom Cron Schedules

The `BACKUP_CRON` environment variable accepts standard cron syntax to define backup schedules.

**Cron Format:** `"minute hour day month weekday"`

**Fields:**
- `minute`: 0-59
- `hour`: 0-23 (0 = midnight, 12 = noon)
- `day`: 1-31
- `month`: 1-12
- `weekday`: 0-7 (0 and 7 = Sunday, 1 = Monday, etc.)

**Special Characters:**
- `*` = any value
- `*/n` = every n units
- `,` = list of values
- `-` = range of values

**Common Schedule Examples:**

Daily backups:
```bash
-e BACKUP_CRON="0 2 * * *"      # Every day at 2:00 AM
-e BACKUP_CRON="30 3 * * *"     # Every day at 3:30 AM
-e BACKUP_CRON="0 0 * * *"      # Every day at midnight
```

Multiple times per day:
```bash
-e BACKUP_CRON="0 */6 * * *"    # Every 6 hours (00:00, 06:00, 12:00, 18:00)
-e BACKUP_CRON="0 */4 * * *"    # Every 4 hours
-e BACKUP_CRON="0 0,12 * * *"   # Twice daily (midnight and noon)
-e BACKUP_CRON="0 2,14 * * *"   # Twice daily (2 AM and 2 PM)
```

Weekly backups:
```bash
-e BACKUP_CRON="0 0 * * 0"      # Every Sunday at midnight
-e BACKUP_CRON="0 3 * * 1"      # Every Monday at 3:00 AM
-e BACKUP_CRON="0 0 * * 6"      # Every Saturday at midnight
```

Weekday backups:
```bash
-e BACKUP_CRON="0 3 * * 1-5"    # Monday through Friday at 3:00 AM
-e BACKUP_CRON="0 22 * * 1-5"   # Monday through Friday at 10:00 PM
```

Monthly backups:
```bash
-e BACKUP_CRON="0 1 1 * *"      # First day of every month at 1:00 AM
-e BACKUP_CRON="0 2 15 * *"     # 15th day of every month at 2:00 AM
-e BACKUP_CRON="0 0 1 1 *"      # January 1st at midnight (yearly)
```

Hourly backups:
```bash
-e BACKUP_CRON="0 * * * *"      # Every hour at minute 0
-e BACKUP_CRON="30 * * * *"     # Every hour at minute 30
-e BACKUP_CRON="*/15 * * * *"   # Every 15 minutes
```

### Volume Mounts

Mount configuration file and temporary storage:

```bash
docker run -d \
  -v $(pwd)/gobackup.yml:/etc/gobackup/gobackup.yml:ro \
  -v backup-temp:/tmp/gobackup \
  gobackup-sqlserver:latest
```

## Backup File Format

Backups are stored as `.bacpac` files in MinIO with the following path structure:

```
{MINIO_PATH}/{model_name}/{timestamp}/{database_name}.bacpac
```

Example:
```
backups/sqlserver/sqlserver_backup/20231224_020000/myapp_production.bacpac
```

## Restoring Backups

To restore a backup, download the `.bacpac` file from MinIO and use sqlpackage:

```bash
sqlpackage /Action:Import \
  /SourceFile:myapp_production.bacpac \
  /TargetServerName:sqlserver.example.com \
  /TargetDatabaseName:myapp_restored \
  /TargetUser:sa \
  /TargetPassword:YourPassword
```

## Monitoring

### Logs

View container logs:

```bash
docker logs -f gobackup-sqlserver
```

Logs include:
- Backup start and completion times
- Backup file sizes
- Upload status
- Error details with troubleshooting information

### Health Checks

The container includes a health check that monitors the GoBackup process:

```bash
docker inspect --format='{{.State.Health.Status}}' gobackup-sqlserver
```

## Troubleshooting

### Connection Issues

**SQL Server connection fails:**
- Verify `MSSQL_HOST` and `MSSQL_PORT` are correct
- Check SQL Server is accessible from container network
- Verify SQL Server authentication mode allows SQL logins
- Check firewall rules allow connections on port 1433

**MinIO connection fails:**
- Verify `MINIO_ENDPOINT` is correct and accessible
- Check `MINIO_ACCESS_KEY` and `MINIO_SECRET_KEY` are valid
- Ensure MinIO bucket exists and is accessible
- Verify network connectivity to MinIO

### Backup Failures

**sqlpackage fails:**
- Check SQL Server user has necessary permissions (db_backupoperator role)
- Verify database name is correct
- Check available disk space in container
- Review sqlpackage error output in logs

**"Unsupported elements" error:**
- The Export action doesn't support ignoring unsupported elements
- **Recommended solution:** Remove unsupported elements from the database
- Common unsupported elements: certificates, symmetric keys, certain permissions, encrypted objects
- **Alternative:** Use sqlpackage Extract action manually to create .dacpac files with `/p:ExtractAllTableData=True /p:VerifyExtraction=False`

**Upload fails:**
- Verify MinIO credentials are correct
- Check MinIO bucket exists
- Verify network connectivity
- Local backup file is retained in `/tmp/gobackup` for manual recovery

### Permission Issues

**Database access denied:**
```sql
-- Grant necessary permissions to backup user
USE master;
GO
ALTER SERVER ROLE [dbcreator] ADD MEMBER [your_backup_user];
GO
```

### Disk Space

**Insufficient disk space:**
- Mount a volume for `/tmp/gobackup` with adequate space
- Monitor disk usage during backups
- Consider backup retention policies in MinIO

## Building from Source

```bash
git clone <repository-url>
cd gobackup-sqlserver-docker
docker build -t gobackup-sqlserver:latest .
```

## License

[Your License Here]

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## Support

For issues and questions:
- Open an issue on GitHub
- Check the troubleshooting section above
- Review container logs for error details
