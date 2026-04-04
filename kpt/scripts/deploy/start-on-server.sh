#!/bin/bash

# Configuration
REMOTE_USER="bisq"
REMOTE_HOST="89.23.100.234"
REMOTE_DIR="/home/bisq/kpt/kpt-tron"

echo "=== Starting FullNode on $REMOTE_HOST ==="

ssh "$REMOTE_USER@$REMOTE_HOST" "bash -s" << EOF
    APP_DIR="$REMOTE_DIR"
    LOG_FILE="$REMOTE_DIR/logs/tron.log"

    if pgrep -f 'FullNode.jar' > /dev/null; then
        PID=\$(pgrep -f 'FullNode.jar')
        echo "ℹ️  FullNode is already running (PID: \$PID)"
        exit 0
    fi

    mkdir -p "\$APP_DIR/logs"

    # Try to find Java 8
    if [ -f "/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java" ]; then
        JAVA_CMD="/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java"
    elif [ -f "/usr/lib/jvm/java-8-openjdk-amd64/bin/java" ]; then
        JAVA_CMD="/usr/lib/jvm/java-8-openjdk-amd64/bin/java"
    else
        JAVA_CMD="java"
        echo "⚠️  Explicit Java 8 path not found, using default 'java'. This might fail if default is not Java 8."
    fi

    echo "Using Java: \$JAVA_CMD"
    cd "\$APP_DIR"
    nohup \$JAVA_CMD -Dapplication.appName=kpt-tron-fullnode -jar "\$APP_DIR/FullNode.jar" -c "\$APP_DIR/config.conf" -d "\$APP_DIR/output-directory" > "\$LOG_FILE" 2>&1 &

    echo "Process started. Waiting for initialization..."
    sleep 5

    if pgrep -f 'FullNode.jar' > /dev/null; then
        PID=\$(pgrep -f 'FullNode.jar')
        echo "✅ FullNode started (PID: \$PID)"
    else
        echo "❌ FullNode failed to start."
        tail -n 20 "\$LOG_FILE"
        exit 1
    fi
EOF
