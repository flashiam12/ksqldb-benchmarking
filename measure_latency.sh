#!/bin/bash

# Default values
INTERVAL=1
ITERATIONS=10
WARMUP=3
OUTPUT_FILE="query_latency.csv"

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Measure ksqlDB query latency"
    echo
    echo "Options:"
    echo "  -i, --interval SECONDS    Time between queries (default: 1)"
    echo "  -n, --iterations NUMBER   Number of iterations to run (default: 10, 0 for infinite)"
    echo "  -w, --warmup NUMBER       Number of warmup iterations (default: 3)"
    echo "  -o, --output FILE        Output CSV file (default: query_latency.csv)"
    echo "  -h, --help               Show this help message"
    echo
    echo "Example:"
    echo "  $0 -i 2 -n 100 -w 5 -o my_results.csv"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interval)
            INTERVAL="$2"
            shift 2
            ;;
        -n|--iterations)
            ITERATIONS="$2"
            shift 2
            ;;
        -w|--warmup)
            WARMUP="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Load environment variables
source .env

# Validate environment variables
if [[ -z "${KSQLDB_ENDPOINT}" || -z "${KSQLDB_API_KEY}" || -z "${KSQLDB_API_SECRET}" ]]; then
    echo "Error: Missing required environment variables. Please check your .env file."
    echo "Required variables: KSQLDB_ENDPOINT, KSQLDB_API_KEY, KSQLDB_API_SECRET"
    exit 1
fi

# ksqlDB endpoint configuration
KSQLDB_ENDPOINT="${KSQLDB_ENDPOINT}"
KSQLDB_API_KEY="${KSQLDB_API_KEY}"
KSQLDB_API_SECRET="${KSQLDB_API_SECRET}"

# Arrays for statistics
declare -a LATENCIES
declare -a SUCCESS_CODES

# Query from queries.md
# QUERY="SELECT * FROM QUERYABLE_ORDER_ONHOLD_TABLE_V2 WHERE composite_key->MGMTCODE = 'MGMT00' AND composite_key->DLRCODE = 'D010' AND composite_key->SRCID = 'SRC147' AND composite_key->ACTNCODE = 'NEW' AND composite_key->TRXNREVN = '2';"
QUERY="SELECT * FROM QUERYABLE_ORDER_ONHOLD_TABLE_V2 WHERE composite_key->MGMTCODE = 'MGMT00' AND composite_key->DLRCODE = 'D010' AND composite_key->SRCID = 'SRC147';"


# Function to make the ksqlDB query and measure latency
run_query() {
    local phase=$1
    local start_time
    local end_time
    local response
    local query_time
    local http_code
    local iteration=${#LATENCIES[@]}
    
    # Prepare the query payload
    local data='{"ksql":"'"$QUERY"'", "streamsProperties": {"ksql.streams.auto.offset.reset": "earliest"}}'
    
    echo "Running query at $(date '+%Y-%m-%d %H:%M:%S')"
    
    # Make the request and capture timing
    start_time=$(date +%s.%N)
    
    response=$(curl -s -w "\n%{http_code}" \
        -X POST "${KSQLDB_ENDPOINT}/query" \
        -H "Content-Type: application/vnd.ksql.v1+json" \
        -H "Accept: application/vnd.ksql.v1+json" \
        -u "${KSQLDB_API_KEY}:${KSQLDB_API_SECRET}" \
        -d "$data")
    
    end_time=$(date +%s.%N)
    
    # Extract HTTP status code from response
    http_code=$(echo "$response" | tail -n1)
    # Extract actual response body (without status code)
    response_body=$(echo "$response" | sed '$d')
    
    # Calculate query time in milliseconds
    query_time=$(echo "($end_time - $start_time) * 1000" | bc)
    
    echo "HTTP Status: $http_code"
    echo "Query latency: ${query_time}ms"
    
    # Check if we got a successful response
    if [ "$http_code" -eq 200 ]; then
        # Count the number of records returned
        record_count=$(echo "$response_body" | grep -c "row")
        echo "Records returned: $record_count"
        
        # Only store statistics for measurement phase
        if [ "$phase" = "measurement" ]; then
            LATENCIES+=($query_time)
            SUCCESS_CODES+=($http_code)
        fi
        
        # Save timing data
        echo "$iteration,$(date '+%Y-%m-%d %H:%M:%S'),$query_time,$record_count,$http_code,$phase" >> "$OUTPUT_FILE"
    else
        echo "Error in query execution:"
        echo "$response_body"
        
        if [ "$phase" = "measurement" ]; then
            LATENCIES+=($query_time)
            SUCCESS_CODES+=($http_code)
        fi
        
        echo "$iteration,$(date '+%Y-%m-%d %H:%M:%S'),$query_time,0,$http_code,$phase" >> "$OUTPUT_FILE"
    fi
}

# Function to calculate statistics
calculate_stats() {
    local count=${#LATENCIES[@]}
    
    if [ "$count" -eq 0 ]; then
        echo
        echo "=== Performance Statistics ==="
        echo "No measurements collected. All queries failed."
        echo "======================="
        return
    fi
    
    local total=0
    local max=0
    local min=999999999
    local success_count=0

    # Process measurements
    for i in "${!LATENCIES[@]}"; do
        local lat=${LATENCIES[$i]}
        total=$(echo "$total + $lat" | bc)
        
        if (( $(echo "$lat > $max" | bc -l) )); then
            max=$lat
        fi
        
        if (( $(echo "$lat < $min" | bc -l) )); then
            min=$lat
        fi

        if [[ "${SUCCESS_CODES[$i]}" -eq 200 ]]; then
            ((success_count++))
        fi
    done

    # Sort latencies for percentile calculation
    sorted=($(printf "%s\n" "${LATENCIES[@]}" | sort -n))
    
    # Calculate basic statistics
    local avg=$(echo "scale=2; $total / $count" | bc)
    local success_rate=$(echo "scale=2; ($success_count * 100) / $count" | bc)
    
    # Calculate percentiles
    local p95=""
    local p99=""
    if [ "$count" -gt 1 ]; then
        local p95_idx=$(echo "($count * 95 / 100) - 1" | bc)
        local p99_idx=$(echo "($count * 99 / 100) - 1" | bc)
        p95_idx=${p95_idx%.*}  # Convert to integer
        p99_idx=${p99_idx%.*}  # Convert to integer
        p95=${sorted[$p95_idx]}
        p99=${sorted[$p99_idx]}
    else
        p95=$avg
        p99=$avg
    fi

    echo
    echo "=== Performance Statistics ==="
    echo "Total Queries: $count"
    echo "Success Rate: ${success_rate}%"
    if [ "$count" -gt 0 ]; then
        echo "Min Latency: ${min}ms"
        echo "Max Latency: ${max}ms"
        echo "Avg Latency: ${avg}ms"
        echo "P95 Latency: ${p95}ms"
        echo "P99 Latency: ${p99}ms"
    fi
    echo "======================="
}

# Trap Ctrl+C to show statistics before exiting
trap 'calculate_stats; exit 0' SIGINT

# Create or clear the CSV file for results
echo "iteration,timestamp,latency_ms,records_returned,http_status,phase" > "$OUTPUT_FILE"

# Warmup phase
if [ "$WARMUP" -gt 0 ]; then
    echo "Starting warmup phase with $WARMUP iterations..."
    for ((i=1; i<=WARMUP; i++)); do
        echo -e "\nWarmup Query #$i"
        run_query "warmup"
        sleep "$INTERVAL"
    done
    echo "Warmup complete"
fi

# Main measurement phase
echo -e "\nStarting measurement phase..."
if [ "$ITERATIONS" -eq 0 ]; then
    echo "Running infinite iterations (Ctrl+C to stop)"
    count=1
    while true; do
        echo -e "\nQuery #$count"
        run_query "measurement"
        count=$((count + 1))
        sleep "$INTERVAL"
    done
else
    echo "Running $ITERATIONS iterations"
    for ((i=1; i<=ITERATIONS; i++)); do
        echo -e "\nQuery #$i"
        run_query "measurement"
        sleep "$INTERVAL"
    done
    calculate_stats
fi
