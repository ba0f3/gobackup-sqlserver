# GoBackup SQL Server Docker Image
# Combines GoBackup with Microsoft sqlpackage for automated SQL Server backups to MinIO

FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set working directory
WORKDIR /app

# Install system dependencies required for sqlpackage and GoBackup
# libicu70 is required for sqlpackage .NET runtime
RUN apt-get update && \
    apt-get install -y \
    libunwind8 \
    libicu70 \
    wget \
    unzip \
    ca-certificates \
    cron \
    jq \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Microsoft sqlpackage
# Download from official Microsoft URL and install to /usr/local/sqlpackage
RUN wget -q https://aka.ms/sqlpackage-linux -O /tmp/sqlpackage.zip && \
    mkdir -p /usr/local/sqlpackage && \
    unzip -q /tmp/sqlpackage.zip -d /usr/local/sqlpackage && \
    chmod +x /usr/local/sqlpackage/sqlpackage && \
    ln -s /usr/local/sqlpackage/sqlpackage /usr/local/bin/sqlpackage && \
    rm /tmp/sqlpackage.zip

# Install GoBackup from GitHub releases
# Using latest stable version
RUN GOBACKUP_VERSION=$(curl -s https://api.github.com/repos/gobackup/gobackup/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/') && \
    echo "Installing GoBackup version: ${GOBACKUP_VERSION}" && \
    wget -q "https://github.com/gobackup/gobackup/releases/download/v${GOBACKUP_VERSION}/gobackup-linux-amd64.tar.gz" -O /tmp/gobackup.tar.gz && \
    tar -xzf /tmp/gobackup.tar.gz -C /tmp && \
    mv /tmp/gobackup /usr/local/bin/gobackup && \
    chmod +x /usr/local/bin/gobackup && \
    rm /tmp/gobackup.tar.gz && \
    gobackup -v

# Create required directories for configuration and temporary files
RUN mkdir -p /etc/gobackup && \
    mkdir -p /tmp/gobackup && \
    chmod 755 /etc/gobackup && \
    chmod 1777 /tmp/gobackup

# Set environment variables for GoBackup
ENV GOBACKUP_CONFIG_DIR=/etc/gobackup
ENV GOBACKUP_WORKDIR=/tmp/gobackup

# Reset DEBIAN_FRONTEND
ENV DEBIAN_FRONTEND=

# Copy entrypoint script and set executable permissions
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Copy configuration template
COPY gobackup.yml.template /app/gobackup.yml.template

# Define entrypoint
ENTRYPOINT ["/entrypoint.sh"]

# Health check to verify GoBackup process is running
# Check every 30 seconds, timeout after 10 seconds, start checking after 30 seconds
# Consider unhealthy after 3 consecutive failures
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD pgrep -f "gobackup" > /dev/null || exit 1
