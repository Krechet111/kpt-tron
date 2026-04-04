#!/bin/bash
set -e

# Configuration
REMOTE_USER="bisq"
REMOTE_HOST="89.23.100.234"
REMOTE_DIR="/home/bisq/kpt/kpt-tron"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "=== Starting Deployment to $REMOTE_HOST ==="
echo "Project Root: $PROJECT_ROOT"

# Set Java 8 for build compatibility (‼️ change path for different OS)
export JAVA_HOME="/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home"
echo "Using JAVA_HOME: $JAVA_HOME"

# 1. Build
echo ">>> Building FullNode.jar..."
cd "$PROJECT_ROOT"
./gradlew :framework:buildFullNodeJar -x test

# 2. Prepare Remote Directory
echo ">>> Preparing remote environment..."
ssh "$REMOTE_USER@$REMOTE_HOST" "mkdir -p $REMOTE_DIR/logs"

# 3. Stop Remote Service
echo ">>> Stopping remote service..."
ssh "$REMOTE_USER@$REMOTE_HOST" "bash -s" << 'EOF'
    if pgrep -f 'FullNode.jar' > /dev/null; then
        pkill -f 'FullNode.jar'
        echo "✅ Signal sent to stop FullNode."
        sleep 5
        if pgrep -f 'FullNode.jar' > /dev/null; then
            echo "⚠️  Process still running, forcing kill..."
            pkill -9 -f 'FullNode.jar'
        fi
        echo "✅ FullNode stopped."
    else
        echo "ℹ️  FullNode was not running."
    fi
EOF

# 4. Transfer Files
echo ">>> Transferring artifacts..."
rsync -avz "$PROJECT_ROOT/framework/build/libs/FullNode.jar" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/"
rsync -avz "$PROJECT_ROOT/framework/src/main/resources/config.conf" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/"

# 5. Start Remote Service
echo ">>> Starting remote service..."
ssh "$REMOTE_USER@$REMOTE_HOST" "bash -s" << EOF
    APP_DIR="$REMOTE_DIR"
    LOG_FILE="$REMOTE_DIR/logs/tron.log"

    if [ -f "/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java" ]; then
        JAVA_CMD="/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java"
    elif [ -f "/usr/lib/jvm/java-8-openjdk-amd64/bin/java" ]; then
        JAVA_CMD="/usr/lib/jvm/java-8-openjdk-amd64/bin/java"
    else
        JAVA_CMD="java"
        echo "⚠️  Explicit Java 8 path not found, using default 'java'."
    fi

    cd "\$APP_DIR"
    nohup \$JAVA_CMD -Dapplication.appName=kpt-tron-fullnode -jar "\$APP_DIR/FullNode.jar" -c "\$APP_DIR/config.conf" -d "\$APP_DIR/output-directory" > "\$LOG_FILE" 2>&1 &

    echo "Process started. Waiting for initialization..."
    sleep 10
EOF

# 6. Verify
echo "=== Verifying Deployment ==="
ssh "$REMOTE_USER@$REMOTE_HOST" "bash -s" << 'EOF'
    if pgrep -f 'FullNode.jar' > /dev/null; then
        PID=$(pgrep -f 'FullNode.jar')
        echo "✅ SUCCESS: FullNode is running (PID: $PID)"
    else
        echo "❌ ERROR: FullNode failed to start."
        tail -n 20 /home/bisq/kpt/kpt-tron/logs/tron.log
        exit 1
    fi
EOF

echo "=== Deployment Complete ==="
