# KPT Scripts

Utility and deployment scripts for the KPT TRON node.

## Directory Structure

```
kpt/scripts/
├── get-node-height.sh      # Get current block number from local node
├── getnowblock.sh          # Get current block (full JSON) from local node
├── getbalance.sh           # Get account info/balance by base58 address
├── getaccaunt.sh           # Get account info by hex address
├── validateaddress.sh      # Validate a TRON address via TronGrid API
└── deploy/
    ├── README.md               # Deploy scripts documentation
    ├── deploy-to-server.sh     # Full build & deploy to remote server
    ├── start-on-server.sh      # Start FullNode service on remote server
    ├── stop-on-server.sh       # Stop FullNode service on remote server
    ├── check-server.sh         # Check service status on remote server
    └── remove-from-server.sh   # Remove all project data from remote server
```

---

## Node Query Scripts

These scripts query the TRON node HTTP API directly.

**Default node:** `http://89.23.100.234:8091`

### `get-node-height.sh`

Returns the current block number from the local node.

```bash
bash get-server-node-height.sh
# Output: 12345678
```

### `getnowblock.sh`

Returns the full current block JSON from the local node.

```bash
bash get-server-current-block.sh
```

### `getbalance.sh`

Returns account info (including balance) for a base58-encoded address using the local node.

Edit the `ADDR_BASE58` variable in the script to query a different address.

```bash
bash get-balance.sh
```

### `getaccaunt.sh`

Returns account info for a hex-encoded address using the local node.

Edit the `FROM_HEX` variable in the script to query a different address.

```bash
bash get-accaunt.sh
```

### `validateaddress.sh`

Validates a TRON address using the public TronGrid API (`https://api.trongrid.io`).

Edit the `ADDR` variable in the script to check a different address.

```bash
bash validate-address.sh
```

---

## Deploy Scripts

These scripts manage the remote server deployment over SSH. See [`deploy/README.md`](deploy/README.md) for full documentation.

**Remote host:** `bisq@89.23.100.234`
**Remote directory:** `/home/bisq/kpt/kpt-tron`

### Prerequisites

- SSH access to `bisq@89.23.100.234`
- Java 8 (`zulu-8.jdk`) installed locally (for build)
- Java 8 (`java-8-openjdk-amd64`) installed on the remote server
- `rsync` installed locally

---

### `deploy/deploy-to-server.sh`

Full deployment pipeline: builds `FullNode.jar` locally, transfers artifacts via `rsync`, and starts the service.

```bash
bash kpt/scripts/deploy/deploy-to-server.sh
```

Steps performed:
1. Builds `FullNode.jar` via Gradle (`buildFullNodeJar`)
2. Stops the currently running service (if any)
3. Transfers `FullNode.jar` and `config.conf` to the server via `rsync`
4. Starts the service and verifies it is running

---

### `deploy/start-on-server.sh`

Starts the FullNode service on the remote server (no build or file transfer).

```bash
bash kpt/scripts/deploy/start-on-server.sh
```

---

### `deploy/stop-on-server.sh`

Stops the FullNode service on the remote server (SIGTERM, then SIGKILL if needed).

```bash
bash kpt/scripts/deploy/stop-on-server.sh
```

---

### `deploy/check-server.sh`

Checks whether the FullNode service is running, the HTTP API status (port 8091), and the last 10 log lines.

```bash
bash kpt/scripts/deploy/check-server.sh
```

---

### `deploy/remove-from-server.sh`

**Destructive.** Stops the service and removes the entire project directory (`/home/bisq/kpt/kpt-tron`) from the remote server. Prompts for confirmation before proceeding.

```bash
bash kpt/scripts/deploy/remove-from-server.sh
```
