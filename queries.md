# ksqlDB Queries Documentation

## Table Schema and Sample Data

### Orders Table Creation
```sql
CREATE TABLE orders (
  key STRING PRIMARY KEY,
  orderKey STRING,
  correlIDHex STRING,
  onholdFlag STRING,
  trxnRevn STRING,
  trxnType STRING,
  dlrCode STRING,
  srcID STRING,
  targetType STRING,
  mgmtCode STRING,
  actnCode STRING,
  messagePayload STRING
)
WITH (
  KAFKA_TOPIC = 'orders_topic',
  KEY_FORMAT = 'AVRO',
  VALUE_FORMAT = 'AVRO',
  PARTITIONS = 6
);

-- or with the schema ids from schema registry

CREATE TABLE orders
WITH (
  KAFKA_TOPIC = 'orders_topic',
  KEY_FORMAT = 'AVRO',
  VALUE_FORMAT = 'AVRO',
  PARTITIONS = 6,
  VALUE_SCHEMA_ID = 100146,
  KEY_SCHEMA_ID = 100145
);
```

### Sample Data Insertion
```sql
INSERT INTO orders (key, orderKey, correlIDHex, onholdFlag, trxnRevn, trxnType, dlrCode, srcID, targetType, mgmtCode, actnCode, messagePayload) VALUES ('ORDERS-KEY-001', 'ORD-123', 'abc123hex', 'ONHOLD', '1', 'SALE', 'D001', 'SRC789', 'TYPEX', 'MGMT99', 'NEW', '{"foo":"bar"}');
INSERT INTO orders (key, orderKey, correlIDHex, onholdFlag, trxnRevn, trxnType, dlrCode, srcID, targetType, mgmtCode, actnCode, messagePayload) VALUES ('ORDERS-KEY-002', 'ORD-124', 'def456hex', 'OFFHOLD', '2', 'RETURN', 'D002', 'SRC456', 'TYPEY', 'MGMT88', 'UPDATE', '{"item":"book"}');
INSERT INTO orders (key, orderKey, correlIDHex, onholdFlag, trxnRevn, trxnType, dlrCode, srcID, targetType, mgmtCode, actnCode, messagePayload) VALUES ('ORDERS-KEY-003', 'ORD-125', 'ghi789hex', 'ONHOLD', '1', 'SALE', 'D003', 'SRC123', 'TYPEZ', 'MGMT77', 'CANCEL', '{"status":"pending"}');
INSERT INTO orders (key, orderKey, correlIDHex, onholdFlag, trxnRevn, trxnType, dlrCode, srcID, targetType, mgmtCode, actnCode, messagePayload) VALUES ('ORDERS-KEY-004', 'ORD-126', 'jkl012hex', 'ONHOLD', '3', 'SALE', 'D004', 'SRC321', 'TYPEX', 'MGMT66', 'NEW', '{"price":100}');
INSERT INTO orders (key, orderKey, correlIDHex, onholdFlag, trxnRevn, trxnType, dlrCode, srcID, targetType, mgmtCode, actnCode, messagePayload) VALUES ('ORDERS-KEY-005', 'ORD-127', 'mno345hex', 'OFFHOLD', '1', 'RETURN', 'D005', 'SRC654', 'TYPEY', 'MGMT55', 'UPDATE', '{"quantity":5}');
INSERT INTO orders (key, orderKey, correlIDHex, onholdFlag, trxnRevn, trxnType, dlrCode, srcID, targetType, mgmtCode, actnCode, messagePayload) VALUES ('ORDERS-KEY-006', 'ORD-128', 'pqr678hex', 'ONHOLD', '2', 'SALE', 'D006', 'SRC987', 'TYPEZ', 'MGMT44', 'CANCEL', '{"reason":"damaged"}');
INSERT INTO orders (key, orderKey, correlIDHex, onholdFlag, trxnRevn, trxnType, dlrCode, srcID, targetType, mgmtCode, actnCode, messagePayload) VALUES ('ORDERS-KEY-007', 'ORD-129', 'stu901hex', 'OFFHOLD', '1', 'RETURN', 'D007', 'SRC159', 'TYPEX', 'MGMT33', 'NEW', '{"foo":"baz"}');
INSERT INTO orders (key, orderKey, correlIDHex, onholdFlag, trxnRevn, trxnType, dlrCode, srcID, targetType, mgmtCode, actnCode, messagePayload) VALUES ('ORDERS-KEY-008', 'ORD-130', 'vwx234hex', 'ONHOLD', '4', 'SALE', 'D008', 'SRC753', 'TYPEY', 'MGMT22', 'UPDATE', '{"promo":"yes"}');
INSERT INTO orders (key, orderKey, correlIDHex, onholdFlag, trxnRevn, trxnType, dlrCode, srcID, targetType, mgmtCode, actnCode, messagePayload) VALUES ('ORDERS-KEY-009', 'ORD-131', 'yz0123hex', 'ONHOLD', '1', 'RETURN', 'D009', 'SRC852', 'TYPEZ', 'MGMT11', 'CANCEL', '{"approved":false}');
INSERT INTO orders (key, orderKey, correlIDHex, onholdFlag, trxnRevn, trxnType, dlrCode, srcID, targetType, mgmtCode, actnCode, messagePayload) VALUES ('ORDERS-KEY-010', 'ORD-132', 'bcd345hex', 'OFFHOLD', '2', 'SALE', 'D010', 'SRC147', 'TYPEX', 'MGMT00', 'NEW', '{"custom":"value"}');
```

## Stream Creation and Transformations

### Create Base Stream
```sql
CREATE STREAM orders_stream
  WITH (
    KAFKA_TOPIC = 'orders_topic',
    VALUE_FORMAT = 'AVRO',
    KEY_FORMAT = 'AVRO',
    VALUE_SCHEMA_ID = 100146,
    KEY_SCHEMA_ID = 100145
  );
```

### Create Composite Key Stream
```sql
CREATE STREAM order_topic_composite_v3
  WITH (
    KAFKA_TOPIC = 'order_topic_composite',
    VALUE_FORMAT = 'AVRO',
    KEY_FORMAT = 'AVRO',
    PARTITIONS = 6
  ) AS
SELECT
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
FROM orders_stream
PARTITION BY STRUCT(
    mgmtCode := mgmtCode,
    dlrCode := dlrCode,
    srcID := srcID,
    actnCode := actnCode,
    trxnRevn := trxnRevn
  )
EMIT CHANGES;
```

## Table Creation with Composite Key

### Create Orders Table with Composite Key
```sql
CREATE TABLE order_onhold_table (
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
  KAFKA_TOPIC = 'order_topic_composite',
  KEY_FORMAT = 'AVRO',
  VALUE_FORMAT = 'AVRO',
  PARTITIONS = 6
);
```

## Query Example

### Query with Composite Key Fields
```sql
CREATE TABLE QUERYABLE_ORDER_ONHOLD_TABLE_V2 WITH (
    KAFKA_TOPIC = 'order_onhold_queryable',
    VALUE_FORMAT = 'AVRO',
    KEY_FORMAT = 'AVRO',
    PARTITIONS = 6
  ) AS
SELECT *
FROM order_onhold_table
EMIT CHANGES;

SELECT * FROM QUERYABLE_ORDER_ONHOLD_TABLE_V2 
WHERE composite_key->MGMTCODE = 'MGMT00'
  AND composite_key->DLRCODE = 'D010'
  AND composite_key->SRCID = 'SRC147'
  AND composite_key->ACTNCODE = 'NEW'
  AND composite_key->TRXNREVN = '2' ;
```

This query demonstrates how to filter records using the composite key fields. It will stream any changes to records that match all the specified composite key field values.
