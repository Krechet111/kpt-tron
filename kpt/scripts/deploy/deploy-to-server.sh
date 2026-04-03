#!/bin/bash
set -e

# Config
HOST="bisq@89.23.100.234"
REMOTE_DIR="/home/bisq/kpt/kpt-tron"
# Resolve Project Root relative to this script (kpt/scripts/deploy.sh -> ../../)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "=== Starting Deployment to $HOST ==="
echo "Project Root: $PROJECT_ROOT"

# Set Java 8 for build compatibility(‼️need to change for different OS)
export JAVA_HOME="/Library/Java/JavaVirtualMachines/zulu-8.jdk/Contents/Home"
echo "Using JAVA_HOME: $JAVA_HOME"

# 1. Build
echo ">>> Building FullNode.jar..."
cd "$PROJECT_ROOT"
./gradlew :framework:buildFullNodeJar -x test

# 2. Prepare Remote & Generate Remote Scripts
echo ">>> preparing remote environment..."
ssh $HOST "mkdir -p $REMOTE_DIR/logs $REMOTE_DIR/scripts"

# Create start.sh on remote
ssh $HOST "cat > $REMOTE_DIR/scripts/start.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")/.."
APP_DIR="$(pwd)"
mkdir -p logs
echo "Starting FullNode..."

# Try to find Java 8
if [ -f "/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java" ]; then
    JAVA_CMD="/usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java"
elif [ -f "/usr/lib/jvm/java-8-openjdk-amd64/bin/java" ]; then
    JAVA_CMD="/usr/lib/jvm/java-8-openjdk-amd64/bin/java"
else
    # Fallback or search in standard paths if known path fails
    JAVA_CMD="java"
    echo "WARNING: Explicit Java 8 path not found, using default 'java'. This might fail if default is not Java 8."
fi

echo "Using Java: $JAVA_CMD"
$JAVA_CMD -version

nohup $JAVA_CMD -jar FullNode.jar -c config.conf > logs/console.log 2>&1 &
echo "FullNode started."
sleep 2
pgrep -f "FullNode.jar"
EOF

# Create stop.sh on remote
ssh $HOST "cat > $REMOTE_DIR/scripts/stop.sh" << 'EOF'
#!/bin/bash
PID=$(pgrep -f "FullNode.jar")
if [ -n "$PID" ]; then
    echo "Stopping FullNode (PID: $PID)..."
    kill $PID
    sleep 5
    PID_CHECK=$(pgrep -f "FullNode.jar")
    if [ -n "$PID_CHECK" ]; then
        echo "Force killing..."
        kill -9 $PID_CHECK
    fi
    echo "Stopped."
else
    echo "FullNode is not running."
fi
EOF

# Create check.sh on remote (status)
ssh $HOST "cat > $REMOTE_DIR/scripts/status.sh" << 'EOF'
#!/bin/bash
PID=$(pgrep -f "FullNode.jar")
if [ -n "$PID" ]; then
    echo "Service is RUNNING (PID: $PID)"
else
    echo "Service is STOPPED"
    exit 1
fi
echo "Checking HTTP API (Port 8091)..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8091/wallet/getnowblock)
if [ "$HTTP_STATUS" == "200" ]; then
    echo "HTTP API is OK (200)"
else
    echo "HTTP API check FAILED (Status: $HTTP_STATUS)"
fi
EOF

# Make them executable
ssh $HOST "chmod +x $REMOTE_DIR/scripts/*.sh"

# 3. Stop Remote Service
echo ">>> Stopping remote service..."
ssh $HOST "bash $REMOTE_DIR/scripts/stop.sh" || echo "Stop failed or not running, continuing..."

# 4. Transfer Files
echo ">>> Transferring artifacts..."
scp "$PROJECT_ROOT/framework/build/libs/FullNode.jar" "$HOST:$REMOTE_DIR/"
scp "$PROJECT_ROOT/framework/src/main/resources/config.conf" "$HOST:$REMOTE_DIR/"

# 5. Start Remote Service
echo ">>> Starting remote service..."
ssh $HOST "bash $REMOTE_DIR/scripts/start.sh"

echo "=== Deployment Complete ==="
