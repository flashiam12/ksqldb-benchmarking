#!/bin/bash

# Load environment variables
source .env

# Validate environment variables
if [[ -z "${KSQLDB_ENDPOINT}" || -z "${KSQLDB_API_KEY}" || -z "${KSQLDB_API_SECRET}" ]]; then
    echo "Error: Missing required environment variables. Please check your .env file."
    echo "Required variables: KSQLDB_ENDPOINT, KSQLDB_API_KEY, KSQLDB_API_SECRET"
    exit 1
fi

# Function to execute ksqlDB query
execute_query() {
    local query="$1"
    local description="$2"
    
    echo "Executing: $description"
    echo "Query: $query"
    
    # Properly escape the query for JSON
    local escaped_query=$(echo "$query" | sed 's/"/\\"/g' | tr '\n' ' ')
    
    response=$(curl -s -X "POST" "$KSQLDB_ENDPOINT/ksql" \
         -H "Content-Type: application/vnd.ksql.v1+json" \
         -H "Accept: application/vnd.ksql.v1+json" \
         -u "$KSQLDB_API_KEY:$KSQLDB_API_SECRET" \
         -d "{
           \"ksql\": \"$escaped_query\",
           \"streamsProperties\": {
             \"ksql.streams.auto.offset.reset\": \"earliest\"
           }
         }")
    
    echo "Response: $response"
    echo "----------------------------------------"
    
    # Sleep for a moment to let the changes propagate
    sleep 2
}

# Execute these queries in order
queries=(
    "DROP TABLE IF EXISTS QUERYABLE_ORDER_ONHOLD_TABLE_V2 DELETE TOPIC;"
    "DROP TABLE IF EXISTS order_onhold_table DELETE TOPIC;"
    "DROP STREAM IF EXISTS order_topic_composite DELETE TOPIC;"
    "DROP STREAM IF EXISTS orders_stream;"
    "DROP TABLE IF EXISTS orders DELETE TOPIC;"
)

echo "Cleaning up existing objects..."
for query in "${queries[@]}"; do
    execute_query "$query" "Cleanup: $query"
done

# Now create everything fresh
echo "Creating new objects..."

# 1. Create initial orders table with schema IDs
execute_query "CREATE TABLE IF NOT EXISTS orders WITH (
    KAFKA_TOPIC = 'orders_topic',
    KEY_FORMAT = 'AVRO',
    VALUE_FORMAT = 'AVRO',
    PARTITIONS = 6,
    VALUE_SCHEMA_ID = 100146,
    KEY_SCHEMA_ID = 100145
);" "Creating orders table"

# 2. Create orders stream
execute_query "CREATE STREAM IF NOT EXISTS orders_stream WITH (
    KAFKA_TOPIC = 'orders_topic',
    VALUE_FORMAT = 'AVRO',
    KEY_FORMAT = 'AVRO',
    VALUE_SCHEMA_ID = 100146,
    KEY_SCHEMA_ID = 100145
);" "Creating orders stream"

# 3. Create composite key stream
execute_query "CREATE STREAM IF NOT EXISTS order_topic_composite WITH (
    KAFKA_TOPIC = 'orders_topic_composite',
    VALUE_FORMAT = 'AVRO',
    KEY_FORMAT = 'AVRO',
    PARTITIONS = 6
) AS SELECT
    STRUCT(
        mgmtCode := mgmtCode,
        dlrCode := dlrCode,
        srcID := srcID,
        actnCode := actnCode,
        trxnRevn := trxnRevn
    ) AS composite_key,
    AS_VALUE(orderKey) AS orderKey,
    AS_VALUE(correlIDHex) AS correlIDHex,
    AS_VALUE(onholdFlag) AS onholdFlag,
    AS_VALUE(trxnType) AS trxnType,
    AS_VALUE(targetType) AS targetType,
    AS_VALUE(messagePayload) AS messagePayload
FROM orders_stream PARTITION BY STRUCT(
    mgmtCode := mgmtCode,
    dlrCode := dlrCode,
    srcID := srcID,
    actnCode := actnCode,
    trxnRevn := trxnRevn
) EMIT CHANGES;" "Creating composite key stream"

# 4. Create orders table with composite key
execute_query "CREATE TABLE IF NOT EXISTS order_onhold_table (
    composite_key STRUCT<
        mgmtCode STRING,
        dlrCode STRING,
        srcID STRING,
        actnCode STRING,
        trxnRevn STRING
    > PRIMARY KEY,
    orderKey STRING,
    correlIDHex STRING,
    onholdFlag STRING,
    trxnType STRING,
    targetType STRING,
    messagePayload STRING
) WITH (
    KAFKA_TOPIC = 'orders_topic_composite',
    KEY_FORMAT = 'AVRO',
    VALUE_FORMAT = 'AVRO',
    PARTITIONS = 6
);" "Creating order_onhold_table"

# 5. Create queryable table
execute_query "CREATE TABLE IF NOT EXISTS QUERYABLE_ORDER_ONHOLD_TABLE_V2 WITH (
    KAFKA_TOPIC = 'orders_onhold_queryable',
    VALUE_FORMAT = 'AVRO',
    KEY_FORMAT = 'AVRO',
    PARTITIONS = 6
) AS SELECT *
FROM order_onhold_table
EMIT CHANGES;" "Creating queryable table"
