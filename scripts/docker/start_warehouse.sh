#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="$PROJECT_DIR/datasets"

CONTAINER_NAME="${MYSQL_CONTAINER_NAME:-sql-data-warehouse-mysql}"
VOLUME_NAME="${MYSQL_VOLUME_NAME:-sql-data-warehouse-mysql-data}"
MYSQL_IMAGE="${MYSQL_IMAGE:-mysql:8.4}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"

required_files=(
    CUST_AZ12.csv
    LOC_A101.csv
    PX_CAT_G1V2.csv
    cust_info.csv
    prd_info.csv
    sales_details.csv
)

for file in "${required_files[@]}"; do
    if [[ ! -r "$DATA_DIR/$file" ]]; then
        printf 'Required dataset is missing or unreadable: %s\n' "$DATA_DIR/$file" >&2
        exit 1
    fi
done

if ! command -v docker >/dev/null 2>&1; then
    printf 'Docker is required. Install and start Docker Desktop, then retry.\n' >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    printf 'Cannot connect to Docker. Start Docker Desktop, then retry.\n' >&2
    exit 1
fi

if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
    if [[ ! -t 0 ]]; then
        printf 'Set MYSQL_ROOT_PASSWORD or run this script interactively to enter it securely.\n' >&2
        exit 1
    fi
    read -r -s -p 'MySQL root password for this local container: ' MYSQL_ROOT_PASSWORD
    printf '\n'
    if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
        printf 'MySQL root password cannot be empty.\n' >&2
        exit 1
    fi
fi

docker volume create "$VOLUME_NAME" >/dev/null

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    mount_targets="$(docker inspect --format '{{range .Mounts}}{{println .Destination}}{{end}}' "$CONTAINER_NAME")"
    if [[ "$mount_targets" != *"/datasets"* ]] || [[ "$mount_targets" != *"/var/lib/mysql"* ]]; then
        printf 'Container "%s" already exists but does not have the expected database and dataset mounts.\n' "$CONTAINER_NAME" >&2
        printf 'Choose another MYSQL_CONTAINER_NAME or remove that container explicitly.\n' >&2
        exit 1
    fi
    published_port="$(docker inspect --format '{{range (index .NetworkSettings.Ports "3306/tcp")}}{{.HostPort}}{{end}}' "$CONTAINER_NAME")"
    if [[ "$published_port" != "$MYSQL_PORT" ]]; then
        printf 'Container "%s" uses host port %s; set MYSQL_PORT=%s when rerunning this script.\n' \
            "$CONTAINER_NAME" "$published_port" "$published_port" >&2
        exit 1
    fi
    if [[ "$(docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME")" != "true" ]]; then
        docker start "$CONTAINER_NAME" >/dev/null
    fi
else
    docker run --detach \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
    --publish "127.0.0.1:${MYSQL_PORT}:3306" \
        --env "MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD" \
        --volume "$VOLUME_NAME:/var/lib/mysql" \
        --volume "$DATA_DIR:/datasets:ro" \
        "$MYSQL_IMAGE" \
        --local-infile=1
fi

printf 'Waiting for MySQL in container "%s"...\n' "$CONTAINER_NAME"
attempt=0
until docker exec --env "MYSQL_PWD=$MYSQL_ROOT_PASSWORD" "$CONTAINER_NAME" \
    mysqladmin --user=root --silent ping >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if (( attempt >= 60 )); then
        printf 'MySQL did not become ready. Recent container logs:\n' >&2
        docker logs --tail 80 "$CONTAINER_NAME" >&2
        exit 1
    fi
    sleep 2
done

run_sql_file() {
    local file="$1"
    printf 'Running %s\n' "${file#"$PROJECT_DIR/"}"
    docker exec --interactive --env "MYSQL_PWD=$MYSQL_ROOT_PASSWORD" "$CONTAINER_NAME" \
        mysql --user=root --local-infile=1 --default-character-set=utf8mb4 < "$file"
}

run_sql_file "$PROJECT_DIR/scripts/init_database.sql"
run_sql_file "$PROJECT_DIR/scripts/bronze/ddl_bronze.sql"
run_sql_file "$PROJECT_DIR/scripts/silver/ddl_silver.sql"
run_sql_file "$PROJECT_DIR/scripts/bronze/proc_load_bronze.sql"
run_sql_file "$PROJECT_DIR/scripts/silver/proc_load_silver.sql"
printf 'Running Silver layer procedure\n'
printf 'CALL silver.load_silver_layer();\n' |
    docker exec --interactive --env "MYSQL_PWD=$MYSQL_ROOT_PASSWORD" "$CONTAINER_NAME" \
        mysql --user=root --local-infile=1 --default-character-set=utf8mb4
run_sql_file "$PROJECT_DIR/scripts/gold/ddl_gold.sql"

printf '\nWarehouse pipeline completed successfully.\n'
printf 'MySQL is available at 127.0.0.1:%s\n' "$MYSQL_PORT"
printf 'Persistent database volume: %s\n' "$VOLUME_NAME"
