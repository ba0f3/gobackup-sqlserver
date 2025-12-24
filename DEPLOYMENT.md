# GoBackup SQL Server Deployment Guide

This guide provides step-by-step instructions for deploying the GoBackup SQL Server backup solution in various environments, including Docker, Docker Compose, and Kubernetes. It also covers backup verification and restore procedures.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Docker Deployment](#docker-deployment)
- [Docker Compose Deployment](#docker-compose-deployment)
- [Kubernetes Deployment](#kubernetes-deployment)
- [Backup Verification](#backup-verification)
- [Restore Procedures](#restore-procedures)
- [Monitoring and Maintenance](#monitoring-and-maintenance)

## Prerequisites

Before deploying, ensure you have:

1. **Docker** (version 20.10 or later) or **Kubernetes** cluster
2. **SQL Server** instance (2017 or later) accessible from the deployment environment
3. **MinIO** or S3-compatible storage accessible from the deployment environment
4. Network connectivity between backup container and SQL Server/MinIO
5. Sufficient storage space for backups (estimate: 1.5x database size)

### Minimum System Requirements

- **CPU**: 1 core (2+ cores recommended for large databases)
- **Memory**: 512MB (1GB+ recommended for large databases)
- **Disk**: Sufficient space for temporary backup files (1.5x database size)
- **Network**: Stable connection to SQL Server and MinIO

## Docker Deployment

### Step 1: Build the Docker Image

Clone the repository and build the image:

```bash
# Clone the repository
git clone <repository-url>
cd gobackup-sqlserver-docker

# Build the image
docker build -t gobackup-sqlserver:latest .

# Verify the build
docker images | grep gobackup-sqlserver
```

### Step 2: Prepare Configuration

Create a `.env` file with your configuration:

```bash
# Copy the example file
cp .env.example .env

# Edit with your settings
nano .env
```

Required variables:
```bash
MSSQL_HOST=your-sqlserver-host
MSSQL_DATABASE=your-database
MSSQL_PASSWORD=your-password
MINIO_ENDPOINT=http://your-minio:9000
MINIO_BUCKET=backups
MINIO_ACCESS_KEY=your-access-key
MINIO_SECRET_KEY=your-secret-key
```

### Step 3: Test with One-Time Backup

Test your configuration with a single backup:

```bash
docker run --rm \
  --env-file .env \
  -e RUN_MODE=once \
  gobackup-sqlserver:latest
```

Check the output for:
- ✅ Configuration validation passed
- ✅ SQL Server connection successful
- ✅ MinIO connection successful
- ✅ Backup completed successfully
- ✅ Upload to MinIO successful

### Step 4: Deploy for Scheduled Backups

Run the container in daemon mode for scheduled backups:

```bash
docker run -d \
  --name gobackup-sqlserver \
  --env-file .env \
  -e RUN_MODE=daemon \
  -e BACKUP_CRON="0 2 * * *" \
  -v backup-temp:/tmp/gobackup \
  --restart unless-stopped \
  gobackup-sqlserver:latest
```

### Step 5: Verify Deployment

Check container status:

```bash
# Check if container is running
docker ps | grep gobackup-sqlserver

# Check container logs
docker logs -f gobackup-sqlserver

# Check health status
docker inspect --format='{{.State.Health.Status}}' gobackup-sqlserver
```

### Docker Run Options

#### Basic Deployment

```bash
docker run -d \
  --name gobackup-sqlserver \
  -e MSSQL_HOST=sqlserver \
  -e MSSQL_DATABASE=mydb \
  -e MSSQL_PASSWORD=password \
  -e MINIO_ENDPOINT=http://minio:9000 \
  -e MINIO_BUCKET=backups \
  -e MINIO_ACCESS_KEY=minioadmin \
  -e MINIO_SECRET_KEY=minioadmin \
  gobackup-sqlserver:latest
```

#### With Custom Configuration File

```bash
docker run -d \
  --name gobackup-sqlserver \
  --env-file .env \
  -v $(pwd)/gobackup.yml:/etc/gobackup/gobackup.yml:ro \
  -v backup-temp:/tmp/gobackup \
  gobackup-sqlserver:latest
```

#### With Resource Limits

```bash
docker run -d \
  --name gobackup-sqlserver \
  --env-file .env \
  --memory="1g" \
  --cpus="1.0" \
  -v backup-temp:/tmp/gobackup \
  gobackup-sqlserver:latest
```

## Docker Compose Deployment

Docker Compose is the recommended deployment method as it simplifies configuration and management.

### Step 1: Prepare Files

Ensure you have these files in your project directory:

```
gobackup-sqlserver-docker/
├── docker-compose.yml
├── .env
├── Dockerfile
├── entrypoint.sh
├── gobackup.yml.template
└── gobackup.yml.example (optional)
```

### Step 2: Configure Environment

Create and configure your `.env` file:

```bash
# Copy the example
cp .env.example .env

# Edit with your settings
nano .env
```

### Step 3: Deploy Services

Deploy all services (GoBackup, SQL Server, MinIO):

```bash
# Start all services
docker-compose up -d

# Check service status
docker-compose ps

# View logs
docker-compose logs -f gobackup
```

### Step 4: Verify Deployment

```bash
# Check all services are running
docker-compose ps

# Check GoBackup logs
docker-compose logs gobackup

# Check SQL Server is healthy
docker-compose exec sqlserver /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "${MSSQL_PASSWORD}" -Q "SELECT @@VERSION"

# Check MinIO is accessible
curl http://localhost:9000/minio/health/live
```

### Step 5: Access MinIO Console

Access the MinIO web console to verify backups:

```bash
# Open in browser
http://localhost:9001

# Login with credentials from .env
# Username: MINIO_ACCESS_KEY
# Password: MINIO_SECRET_KEY
```

### Docker Compose Commands

```bash
# Start services
docker-compose up -d

# Stop services
docker-compose stop

# Restart services
docker-compose restart

# View logs
docker-compose logs -f [service_name]

# Execute command in container
docker-compose exec gobackup bash

# Remove services and volumes
docker-compose down -v

# Rebuild and restart
docker-compose up -d --build
```

### Production Docker Compose Configuration

For production, customize `docker-compose.yml`:

```yaml
version: '3.8'

services:
  gobackup:
    build: .
    container_name: gobackup-sqlserver-prod
    env_file: .env.prod
    volumes:
      - ./gobackup.yml:/etc/gobackup/gobackup.yml:ro
      - backup-temp:/tmp/gobackup
      - /var/log/gobackup:/var/log/gobackup
    restart: always
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 2G
        reservations:
          cpus: '1.0'
          memory: 1G
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    networks:
      - backup-network

volumes:
  backup-temp:
    driver: local

networks:
  backup-network:
    driver: bridge
```

## Kubernetes Deployment

### Step 1: Create Namespace

```bash
kubectl create namespace gobackup
```

### Step 2: Create Secrets

Create secrets for sensitive data:

```bash
# Create SQL Server password secret
kubectl create secret generic mssql-credentials \
  --from-literal=password='YourStrongPassword123!' \
  -n gobackup

# Create MinIO credentials secret
kubectl create secret generic minio-credentials \
  --from-literal=access-key='your-access-key' \
  --from-literal=secret-key='your-secret-key' \
  -n gobackup
```

### Step 3: Create ConfigMap

Create a ConfigMap for GoBackup configuration:

```bash
kubectl create configmap gobackup-config \
  --from-file=gobackup.yml=./gobackup.yml.example \
  -n gobackup
```

### Step 4: Create Deployment

Create `gobackup-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gobackup-sqlserver
  namespace: gobackup
  labels:
    app: gobackup-sqlserver
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gobackup-sqlserver
  template:
    metadata:
      labels:
        app: gobackup-sqlserver
    spec:
      containers:
      - name: gobackup
        image: gobackup-sqlserver:latest
        imagePullPolicy: IfNotPresent
        env:
        - name: MSSQL_HOST
          value: "sqlserver.database.svc.cluster.local"
        - name: MSSQL_PORT
          value: "1433"
        - name: MSSQL_DATABASE
          value: "production"
        - name: MSSQL_USERNAME
          value: "sa"
        - name: MSSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mssql-credentials
              key: password
        - name: MSSQL_TRUST_CERT
          value: "true"
        - name: MINIO_ENDPOINT
          value: "http://minio.storage.svc.cluster.local:9000"
        - name: MINIO_BUCKET
          value: "backups"
        - name: MINIO_REGION
          value: "us-east-1"
        - name: MINIO_PATH
          value: "backups/sqlserver"
        - name: MINIO_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: access-key
        - name: MINIO_SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: secret-key
        - name: BACKUP_CRON
          value: "0 2 * * *"
        - name: RUN_MODE
          value: "daemon"
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "2000m"
        volumeMounts:
        - name: gobackup-config
          mountPath: /etc/gobackup
          readOnly: true
        - name: backup-temp
          mountPath: /tmp/gobackup
        livenessProbe:
          exec:
            command:
            - pgrep
            - -f
            - gobackup
          initialDelaySeconds: 30
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3
        readinessProbe:
          exec:
            command:
            - pgrep
            - -f
            - gobackup
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
      volumes:
      - name: gobackup-config
        configMap:
          name: gobackup-config
      - name: backup-temp
        emptyDir:
          sizeLimit: 10Gi
      restartPolicy: Always
```

### Step 5: Deploy to Kubernetes

```bash
# Apply the deployment
kubectl apply -f gobackup-deployment.yaml

# Check deployment status
kubectl get deployments -n gobackup

# Check pod status
kubectl get pods -n gobackup

# View logs
kubectl logs -f deployment/gobackup-sqlserver -n gobackup
```

### Step 6: Create CronJob (Alternative)

For one-time backups on a schedule, use a CronJob instead:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: gobackup-sqlserver
  namespace: gobackup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: gobackup
            image: gobackup-sqlserver:latest
            env:
            - name: RUN_MODE
              value: "once"
            - name: MSSQL_HOST
              value: "sqlserver.database.svc.cluster.local"
            # ... (other environment variables)
            resources:
              requests:
                memory: "512Mi"
                cpu: "500m"
              limits:
                memory: "2Gi"
                cpu: "2000m"
          restartPolicy: OnFailure
```

Apply the CronJob:

```bash
kubectl apply -f gobackup-cronjob.yaml
```

### Kubernetes Management Commands

```bash
# View deployment
kubectl get deployment gobackup-sqlserver -n gobackup

# View pods
kubectl get pods -n gobackup

# View logs
kubectl logs -f deployment/gobackup-sqlserver -n gobackup

# Execute command in pod
kubectl exec -it deployment/gobackup-sqlserver -n gobackup -- bash

# Scale deployment
kubectl scale deployment gobackup-sqlserver --replicas=1 -n gobackup

# Update deployment
kubectl set image deployment/gobackup-sqlserver gobackup=gobackup-sqlserver:v2 -n gobackup

# Delete deployment
kubectl delete deployment gobackup-sqlserver -n gobackup

# View CronJob status
kubectl get cronjobs -n gobackup

# View CronJob history
kubectl get jobs -n gobackup
```

## Backup Verification

### Verify Backup Execution

#### Check Container Logs

```bash
# Docker
docker logs gobackup-sqlserver

# Docker Compose
docker-compose logs gobackup

# Kubernetes
kubectl logs deployment/gobackup-sqlserver -n gobackup
```

Look for:
```
[INFO] Backup started for model: sqlserver_backup
[INFO] Executing sqlpackage export...
[INFO] Backup file created: /tmp/gobackup/mydb_20241224_020000.bacpac
[INFO] Uploading to MinIO...
[INFO] Upload successful: backups/sqlserver/sqlserver_backup/20241224_020000/mydb.bacpac
[INFO] Backup completed successfully
```

### Verify Backup in MinIO

#### Using MinIO Console

1. Access MinIO Console: `http://your-minio:9001`
2. Navigate to the backup bucket
3. Browse to: `backups/sqlserver/sqlserver_backup/`
4. Verify backup files exist with recent timestamps

#### Using MinIO Client (mc)

```bash
# Configure mc
mc alias set myminio http://your-minio:9000 minioadmin minioadmin

# List backups
mc ls myminio/backups/backups/sqlserver/sqlserver_backup/

# Get backup file details
mc stat myminio/backups/backups/sqlserver/sqlserver_backup/20241224_020000/mydb.bacpac

# Download backup for verification
mc cp myminio/backups/backups/sqlserver/sqlserver_backup/20241224_020000/mydb.bacpac ./
```

### Verify Backup Integrity

#### Check File Size

```bash
# The backup file should be non-zero and reasonable size
ls -lh mydb.bacpac
```

#### Verify .bacpac Structure

```bash
# .bacpac files are ZIP archives
unzip -l mydb.bacpac

# Should contain:
# - model.xml (database schema)
# - Data/ directory (table data)
# - Origin.xml (metadata)
```

### Automated Verification Script

Create a verification script:

```bash
#!/bin/bash
# verify-backup.sh

MINIO_ENDPOINT="http://minio:9000"
MINIO_BUCKET="backups"
MINIO_PATH="backups/sqlserver/sqlserver_backup"
MINIO_ACCESS_KEY="minioadmin"
MINIO_SECRET_KEY="minioadmin"

# Configure mc
mc alias set verify ${MINIO_ENDPOINT} ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY}

# Get latest backup
LATEST_BACKUP=$(mc ls verify/${MINIO_BUCKET}/${MINIO_PATH}/ | tail -1 | awk '{print $NF}')

if [ -z "$LATEST_BACKUP" ]; then
    echo "ERROR: No backups found"
    exit 1
fi

echo "Latest backup: ${LATEST_BACKUP}"

# Get backup details
mc stat verify/${MINIO_BUCKET}/${MINIO_PATH}/${LATEST_BACKUP}

# Check backup age (should be recent)
BACKUP_TIME=$(mc stat verify/${MINIO_BUCKET}/${MINIO_PATH}/${LATEST_BACKUP} | grep "Time" | awk '{print $3}')
echo "Backup time: ${BACKUP_TIME}"

echo "Backup verification complete"
```

## Restore Procedures

### Prerequisites for Restore

1. **sqlpackage** installed on restore machine
2. **Target SQL Server** instance accessible
3. **Backup file** downloaded from MinIO
4. **Sufficient permissions** on target SQL Server (db_owner or dbcreator role)

### Step 1: Download Backup from MinIO

#### Using MinIO Console

1. Access MinIO Console
2. Navigate to backup bucket
3. Browse to backup file
4. Click "Download"

#### Using MinIO Client

```bash
# Configure mc
mc alias set myminio http://your-minio:9000 minioadmin minioadmin

# List available backups
mc ls myminio/backups/backups/sqlserver/sqlserver_backup/

# Download specific backup
mc cp myminio/backups/backups/sqlserver/sqlserver_backup/20241224_020000/mydb.bacpac ./mydb.bacpac
```

#### Using curl (if MinIO is publicly accessible)

```bash
curl -o mydb.bacpac "http://your-minio:9000/backups/backups/sqlserver/sqlserver_backup/20241224_020000/mydb.bacpac"
```

### Step 2: Verify Backup File

```bash
# Check file size
ls -lh mydb.bacpac

# Verify it's a valid ZIP archive
unzip -t mydb.bacpac

# Check contents
unzip -l mydb.bacpac | head -20
```

### Step 3: Restore Database

#### Basic Restore

```bash
sqlpackage /Action:Import \
  /SourceFile:mydb.bacpac \
  /TargetServerName:sqlserver.example.com \
  /TargetDatabaseName:mydb_restored \
  /TargetUser:sa \
  /TargetPassword:YourPassword
```

#### Restore with Options

```bash
sqlpackage /Action:Import \
  /SourceFile:mydb.bacpac \
  /TargetServerName:sqlserver.example.com,1433 \
  /TargetDatabaseName:mydb_restored \
  /TargetUser:sa \
  /TargetPassword:YourPassword \
  /TargetTrustServerCertificate:True \
  /p:DatabaseEdition=Standard \
  /p:DatabaseServiceObjective=S3 \
  /DiagnosticsFile:restore.log
```

#### Restore to Azure SQL Database

```bash
sqlpackage /Action:Import \
  /SourceFile:mydb.bacpac \
  /TargetServerName:myserver.database.windows.net \
  /TargetDatabaseName:mydb_restored \
  /TargetUser:admin@myserver \
  /TargetPassword:YourPassword \
  /p:DatabaseEdition=Standard \
  /p:DatabaseServiceObjective=S3
```

### Step 4: Verify Restore

```bash
# Connect to SQL Server
sqlcmd -S sqlserver.example.com -U sa -P YourPassword

# Check database exists
SELECT name, state_desc, recovery_model_desc 
FROM sys.databases 
WHERE name = 'mydb_restored';
GO

# Check table count
USE mydb_restored;
GO
SELECT COUNT(*) AS TableCount FROM sys.tables;
GO

# Check row counts
SELECT 
    t.name AS TableName,
    SUM(p.rows) AS RowCount
FROM sys.tables t
INNER JOIN sys.partitions p ON t.object_id = p.object_id
WHERE p.index_id IN (0,1)
GROUP BY t.name
ORDER BY RowCount DESC;
GO
```

### Restore Script

Create an automated restore script:

```bash
#!/bin/bash
# restore-backup.sh

BACKUP_FILE=$1
TARGET_SERVER=$2
TARGET_DATABASE=$3
TARGET_USER=${4:-sa}
TARGET_PASSWORD=$5

if [ -z "$BACKUP_FILE" ] || [ -z "$TARGET_SERVER" ] || [ -z "$TARGET_DATABASE" ] || [ -z "$TARGET_PASSWORD" ]; then
    echo "Usage: $0 <backup_file> <target_server> <target_database> [target_user] <target_password>"
    exit 1
fi

echo "Starting restore..."
echo "Backup file: ${BACKUP_FILE}"
echo "Target server: ${TARGET_SERVER}"
echo "Target database: ${TARGET_DATABASE}"

# Verify backup file exists
if [ ! -f "${BACKUP_FILE}" ]; then
    echo "ERROR: Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

# Verify backup file integrity
echo "Verifying backup file integrity..."
unzip -t "${BACKUP_FILE}" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: Backup file is corrupted"
    exit 1
fi

# Perform restore
echo "Restoring database..."
sqlpackage /Action:Import \
  /SourceFile:"${BACKUP_FILE}" \
  /TargetServerName:"${TARGET_SERVER}" \
  /TargetDatabaseName:"${TARGET_DATABASE}" \
  /TargetUser:"${TARGET_USER}" \
  /TargetPassword:"${TARGET_PASSWORD}" \
  /TargetTrustServerCertificate:True \
  /DiagnosticsFile:restore_$(date +%Y%m%d_%H%M%S).log

if [ $? -eq 0 ]; then
    echo "Restore completed successfully"
    echo "Database: ${TARGET_DATABASE}"
else
    echo "ERROR: Restore failed"
    echo "Check restore log for details"
    exit 1
fi
```

Usage:

```bash
chmod +x restore-backup.sh
./restore-backup.sh mydb.bacpac sqlserver.example.com mydb_restored sa YourPassword
```

### Restore Troubleshooting

**Error: Database already exists**
```bash
# Drop existing database first
sqlcmd -S sqlserver -U sa -P password -Q "DROP DATABASE mydb_restored"

# Or use a different database name
sqlpackage /Action:Import /SourceFile:mydb.bacpac /TargetDatabaseName:mydb_restored_v2 ...
```

**Error: Insufficient permissions**
```sql
-- Grant necessary permissions
USE master;
GO
ALTER SERVER ROLE [dbcreator] ADD MEMBER [restore_user];
GO
```

**Error: Timeout during restore**
```bash
# Increase timeout
sqlpackage /Action:Import \
  /SourceFile:mydb.bacpac \
  ... \
  /p:CommandTimeout=7200
```

## Monitoring and Maintenance

### Monitoring Backup Jobs

#### Docker Logs

```bash
# Follow logs in real-time
docker logs -f gobackup-sqlserver

# View last 100 lines
docker logs --tail 100 gobackup-sqlserver

# View logs since specific time
docker logs --since 2024-12-24T02:00:00 gobackup-sqlserver
```

#### Log Aggregation

Configure log forwarding to centralized logging:

```yaml
# docker-compose.yml
services:
  gobackup:
    logging:
      driver: "syslog"
      options:
        syslog-address: "tcp://logserver:514"
        tag: "gobackup"
```

### Health Monitoring

#### Docker Health Check

```bash
# Check health status
docker inspect --format='{{.State.Health.Status}}' gobackup-sqlserver

# View health check logs
docker inspect --format='{{range .State.Health.Log}}{{.Output}}{{end}}' gobackup-sqlserver
```

#### Kubernetes Health Check

```bash
# Check pod health
kubectl get pods -n gobackup

# View pod events
kubectl describe pod <pod-name> -n gobackup

# Check liveness/readiness probes
kubectl get pod <pod-name> -n gobackup -o jsonpath='{.status.conditions}'
```

### Alerting

#### Slack Notifications

Configure in `gobackup.yml`:

```yaml
notifiers:
  slack:
    webhook_url: "${SLACK_WEBHOOK_URL}"
```

#### Email Notifications

```yaml
notifiers:
  email:
    smtp_host: "${SMTP_HOST}"
    smtp_port: 587
    smtp_user: "${SMTP_USER}"
    smtp_password: "${SMTP_PASSWORD}"
    from: "backups@example.com"
    to: "admin@example.com"
```

### Maintenance Tasks

#### Update Docker Image

```bash
# Pull latest image
docker pull gobackup-sqlserver:latest

# Stop and remove old container
docker stop gobackup-sqlserver
docker rm gobackup-sqlserver

# Start new container
docker run -d --name gobackup-sqlserver --env-file .env gobackup-sqlserver:latest
```

#### Clean Up Old Backups

Configure retention in `gobackup.yml`:

```yaml
archive:
  keep_days: 30
  keep_weeks: 8
  keep_months: 12
```

Or use MinIO lifecycle policies:

```bash
mc ilm add --expiry-days 30 myminio/backups/backups/sqlserver/
```

#### Monitor Disk Usage

```bash
# Check container disk usage
docker exec gobackup-sqlserver df -h /tmp/gobackup

# Check MinIO bucket size
mc du myminio/backups/backups/sqlserver/
```

#### Rotate Logs

```yaml
# docker-compose.yml
services:
  gobackup:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

### Performance Tuning

#### Optimize Backup Schedule

- Schedule backups during low-traffic periods
- Stagger multiple database backups
- Consider backup frequency vs. RPO requirements

#### Resource Allocation

```yaml
# docker-compose.yml
services:
  gobackup:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 2G
        reservations:
          cpus: '1.0'
          memory: 1G
```

#### Network Optimization

- Use local network for SQL Server connection
- Place MinIO close to backup container
- Consider network bandwidth for large databases

## Troubleshooting Deployment Issues

### Container Won't Start

```bash
# Check container logs
docker logs gobackup-sqlserver

# Check for missing environment variables
docker inspect gobackup-sqlserver | grep -A 20 Env

# Verify image exists
docker images | grep gobackup-sqlserver
```

### Backup Fails

```bash
# Check SQL Server connectivity
docker exec gobackup-sqlserver sqlpackage /Action:Script \
  /SourceServerName:${MSSQL_HOST} \
  /SourceDatabaseName:${MSSQL_DATABASE}

# Check MinIO connectivity
docker exec gobackup-sqlserver curl -v ${MINIO_ENDPOINT}

# Check disk space
docker exec gobackup-sqlserver df -h
```

### Kubernetes Pod CrashLoopBackOff

```bash
# View pod logs
kubectl logs <pod-name> -n gobackup

# Describe pod for events
kubectl describe pod <pod-name> -n gobackup

# Check secrets exist
kubectl get secrets -n gobackup

# Check configmap exists
kubectl get configmap -n gobackup
```

## Best Practices

1. **Test restores regularly** - Verify backups can be restored successfully
2. **Monitor backup jobs** - Set up alerts for failures
3. **Secure credentials** - Use secrets management, never commit credentials
4. **Document procedures** - Keep deployment and restore procedures updated
5. **Version control** - Track configuration changes in git
6. **Capacity planning** - Monitor storage usage and plan for growth
7. **Disaster recovery** - Have a documented DR plan
8. **Regular updates** - Keep Docker images and dependencies updated
9. **Performance monitoring** - Track backup duration and size trends
10. **Security audits** - Regularly review access controls and permissions

## Additional Resources

- [Docker Documentation](https://docs.docker.com/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [sqlpackage Documentation](https://docs.microsoft.com/en-us/sql/tools/sqlpackage/)
- [MinIO Documentation](https://min.io/docs/)
- [GoBackup Documentation](https://gobackup.github.io/)

