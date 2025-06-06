# ksqlDB Benchmarking

A benchmarking toolkit for measuring ksqlDB query performance and latency across different data throughput scenarios.

## Prerequisites

- Python 3.8+
- Confluent Cloud account with ksqlDB cluster
- Confluent CLI installed
- `jq` command-line tool

## Setup

1. Clone the repository:
```bash
git clone <repository-url>
cd ksqldb-benchmarking
```

2. Create a virtual environment and install dependencies:
```bash
python -m venv venv
source venv/bin/activate  # On Windows use: venv\Scripts\activate
pip install -r requirements.txt
```

3. Create a `.env` file with your Confluent Cloud credentials:
```env
KSQLDB_ENDPOINT="https://your-ksqldb-endpoint"
KSQLDB_API_KEY="your-api-key"
KSQLDB_API_SECRET="your-api-secret"
```

## Project Structure

### Core Files
- `setup_tables.sh` - Sets up required ksqlDB tables and streams
  - Drops existing tables and streams if they exist
  - Creates base orders table with schema IDs (100145, 100146)
  - Sets up orders stream for data flow
  - Creates composite key stream for optimized querying
  - Establishes materialized views and queryable tables
  - All objects use AVRO format with 6 partitions

- `setup_topics.sh` - Manages Kafka topics
  - Deletes existing topics with 'orders_' prefix
  - Creates required topics:
    - orders_topic (source data)
    - orders_topic_composite (transformed data)
    - orders_onhold_queryable (query endpoint)
  - Configures topics with proper partitioning and retention

- `measure_latency.sh` - Comprehensive benchmarking script
  - Options:
    - `-i, --interval`: Time between queries (default: 1s)
    - `-n, --iterations`: Number of test iterations (default: 10)
    - `-w, --warmup`: Warmup iterations count (default: 3)
    - `-o, --output`: CSV output file location
  - Measures:
    - Query latency in milliseconds
    - Success rates
    - Record counts
    - Percentile statistics (P95, P99)
  - Supports infinite running with Ctrl+C for statistics

### Documentation and Schema
- `queries.md` - Complete query documentation
  - Table creation statements with schema definitions
  - Sample data insertion queries
  - Stream creation and transformation logic
  - Composite key structure and usage
  - Example queries for data retrieval
  - Detailed comments and explanations

- `pipeline_diagram.md` - Data flow visualization
  - Step-by-step data transformation flow
  - Component relationships
  - Key transformation points
  - Query optimization explanations

### Source Files
- `producer.py` - Data generation and ingestion
  - Generates sample order data
  - Supports different throughput scenarios
  - Handles AVRO schema compliance
  - Configurable data patterns

### Results and Schemas
- `source_topic_value.avsc` - AVRO schema definition
  - Defines the structure of order data
  - Ensures data type consistency
  - Maps to ksqlDB table schema

- `benchmark_results/` - Performance test results
  - High throughput tests (3.2 Mbps)
  - Low throughput tests (70 Kbps)
  - Source/sink tests with 30K records
  - CSV format with detailed metrics
  - Separate files for different scenarios:
    - `3.2mbps_1_record_query_latency.csv`
    - `70kbps_1_record_query_latency.csv`
    - `30k_source_X_record_query_latency.csv`
    - `30k_sink_X_record_query_latency.csv`

## Running Benchmarks

1. Set up the Kafka topics:
```bash
./setup_topics.sh
```
This initializes the Kafka topics with proper configurations and cleans up any existing topics with the 'orders_' prefix.

2. Create the ksqlDB tables and streams:
```bash
./setup_tables.sh
```
This script:
- Drops existing ksqlDB objects to ensure clean state
- Creates the base orders table with schema IDs
- Sets up the streaming pipeline with composite keys
- Creates materialized views for efficient querying

3. Run the benchmarking with desired parameters:
```bash
# Basic run with defaults
./measure_latency.sh

# Custom configuration example
./measure_latency.sh -i 2 -n 100 -w 5 -o "benchmark_results/custom_test.csv"

# Continuous monitoring until manually stopped
./measure_latency.sh -n 0
```

Available options for measure_latency.sh:
- `-i SECONDS`: Set interval between queries (default: 1)
- `-n NUMBER`: Set number of iterations (default: 10, use 0 for infinite)
- `-w NUMBER`: Set warmup iterations (default: 3)
- `-o FILE`: Specify output CSV file (default: query_latency.csv)

The script will output real-time statistics including:
- Query latency (min, max, avg)
- P95 and P99 percentiles
- Success rates
- Record counts

Press Ctrl+C at any time to see final statistics when running in infinite mode.

The benchmark results will be saved in CSV format in the `benchmark_results` directory.

## Pipeline Overview

The benchmarking pipeline consists of:
1. Base table with schema IDs
2. Base stream creation
3. Composite key transformation
4. Materialized table with composite key
5. Final queryable view

See `pipeline_diagram.md` for a visual representation of the data flow.

## Benchmark Queries

Two main queries are being benchmarked:

1. **Full Composite Key Query:**
```sql
SELECT * 
FROM QUERYABLE_ORDER_ONHOLD_TABLE_V2 
WHERE composite_key->MGMTCODE = 'MGMT00'
  AND composite_key->DLRCODE = 'D010'
  AND composite_key->SRCID = 'SRC147'
  AND composite_key->ACTNCODE = 'NEW'
  AND composite_key->TRXNREVN = '2'
```

2. **Partial Composite Key Query:**
```sql
SELECT * 
FROM QUERYABLE_ORDER_ONHOLD_TABLE_V2 
WHERE composite_key->MGMTCODE = 'MGMT00'
  AND composite_key->DLRCODE = 'D010'
  AND composite_key->SRCID = 'SRC147'
```

The queries test lookup performance using different combinations of the composite key fields:
- Full query uses all 5 fields for precise record lookup
- Partial query uses 3 fields for broader match criteria

## Test Scenarios

The benchmarking suite includes multiple test scenarios:

1. **High Throughput Test (3.2 Mbps)**
   - Tests query performance under high data load
   - Results in: `3.2mbps_1_record_query_latency.csv`

2. **Low Throughput Test (70 Kbps)**
   - Tests query performance under normal conditions
   - Results in: `70kbps_1_record_query_latency.csv`

3. **Source/Sink Tests (30K records)**
   - Tests with varying record volumes
   - Source test results:
     - `30k_source_0_record_query_latency.csv`
     - `30k_source_1_record_query_latency.csv`
   - Sink test results:
     - `30k_sink_0_record_query_latency.csv`
     - `30k_sink_1_record_query_latency.csv`

Each test captures:
- Query latency in milliseconds
- Success/failure rates
- Record counts
- Statistical distributions (min, max, avg, P95, P99)

## Environment Variables

Copy `.env.template` to `.env` and configure the following variables:

### Confluent Cloud Configuration
- `BOOTSTRAP_SERVERS` - Kafka cluster bootstrap servers URL
- `SCHEMA_REGISTRY_URL` - Schema Registry endpoint URL

### Kafka Configuration
- `KAFKA_API_KEY` - Kafka cluster API key
- `KAFKA_API_SECRET` - Kafka cluster API secret
- `KAFKA_TOPIC` - Source topic name (default: orders_topic)
- `TARGET_MESSAGES_PER_MINUTE` - Message throughput target (default: 20000)

### Schema Registry Configuration
- `SR_API_KEY` - Schema Registry API key
- `SR_API_SECRET` - Schema Registry API secret

### ksqlDB Configuration
- `KSQLDB_ENDPOINT` - ksqlDB cluster endpoint (format: https://your-ksqldb-endpoint.confluent.cloud:443)
- `KSQLDB_API_KEY` - ksqlDB API key
- `KSQLDB_API_SECRET` - ksqlDB API secret

You can get these credentials from your Confluent Cloud console:
1. Kafka cluster credentials from the Cluster Overview page
2. Schema Registry credentials from the Schema Registry section
3. ksqlDB credentials from the ksqlDB cluster page

Example `.env` file:
```env
# Confluent Cloud Configuration
BOOTSTRAP_SERVERS=pkc-xxxxx.region.aws.confluent.cloud:9092
SCHEMA_REGISTRY_URL=https://psrc-xxxxx.region.aws.confluent.cloud

# Kafka API Credentials
KAFKA_API_KEY=ABCDEFGHIJKLMNOP
KAFKA_API_SECRET=your-kafka-secret-key

# Schema Registry API Credentials
SR_API_KEY=QRSTUVWXYZ123456
SR_API_SECRET=your-schema-registry-secret

# ksqlDB Credentials
KSQLDB_ENDPOINT=https://pksqlc-xxxxx.region.aws.confluent.cloud:443
KSQLDB_API_KEY=789ABCDEFGHIJKLM
KSQLDB_API_SECRET=your-ksqldb-secret

# Topic Configuration
KAFKA_TOPIC=orders_topic
TARGET_MESSAGES_PER_MINUTE=20000
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

[Add your license information here]
