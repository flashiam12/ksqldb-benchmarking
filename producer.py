import json
import os
import random
import time
import uuid
from datetime import datetime
from typing import Dict, Any
from dotenv import load_dotenv
from confluent_kafka import SerializingProducer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer
from confluent_kafka.serialization import StringSerializer

# Load environment variables
load_dotenv()

# Confluent Cloud configuration
BOOTSTRAP_SERVERS = os.getenv('BOOTSTRAP_SERVERS')
SCHEMA_REGISTRY_URL = os.getenv('SCHEMA_REGISTRY_URL')
KAFKA_API_KEY = os.getenv('KAFKA_API_KEY')
KAFKA_API_SECRET = os.getenv('KAFKA_API_SECRET')
SR_API_KEY = os.getenv('SR_API_KEY')
SR_API_SECRET = os.getenv('SR_API_SECRET')

# Topic configuration
TOPIC = os.getenv('KAFKA_TOPIC', 'orders_topic')
TARGET_MESSAGES_PER_MINUTE = int(os.getenv('TARGET_MESSAGES_PER_MINUTE', '20000'))
SLEEP_TIME = 60 / TARGET_MESSAGES_PER_MINUTE  # Time to sleep between messages

# Load the Avro schema
with open('source_topic_value.avsc', 'r') as f:
    value_schema = json.load(f)

# Sample data for generation
TRANSACTION_TYPES = ['SALE', 'RETURN']
HOLD_FLAGS = ['ONHOLD', 'OFFHOLD']
TARGET_TYPES = ['TYPEX', 'TYPEY', 'TYPEZ']
ACTION_CODES = ['NEW', 'UPDATE', 'CANCEL']

def generate_dealer_code() -> str:
    return f'D{str(random.randint(1, 999)).zfill(3)}'

def generate_src_id() -> str:
    return f'SRC{str(random.randint(100, 999))}'

def generate_mgmt_code() -> str:
    return f'MGMT{str(random.randint(0, 99)).zfill(2)}'

def generate_message_payload() -> str:
    payload_types = [
        lambda: {'foo': random.choice(['bar', 'baz'])},
        lambda: {'item': random.choice(['book', 'pen', 'laptop'])},
        lambda: {'price': random.randint(10, 1000)},
        lambda: {'quantity': random.randint(1, 10)},
        lambda: {'status': random.choice(['pending', 'approved', 'rejected'])},
        lambda: {'reason': random.choice(['damaged', 'late', 'wrong_item'])},
        lambda: {'custom': f'value_{random.randint(1, 100)}'}
    ]
    return json.dumps(random.choice(payload_types)())

def generate_record() -> Dict[str, Any]:
    order_key = f'ORD-{str(random.randint(1, 99999)).zfill(5)}'
    
    # 10% chance to generate a record matching the query criteria
    if random.random() > 0.10:
        return {
            'ORDERKEY': order_key,
            'CORRELIDHEX': uuid.uuid4().hex[:8] + 'hex',
            'ONHOLDFLAG': random.choice(HOLD_FLAGS),
            'TRXNREVN': '2',  # Matches query criteria
            'TRXNTYPE': random.choice(TRANSACTION_TYPES),
            'DLRCODE': 'D010',  # Matches query criteria
            'SRCID': 'SRC147',  # Matches query criteria
            'TARGETTYPE': random.choice(TARGET_TYPES),
            'MGMTCODE': 'MGMT00',  # Matches query criteria
            'ACTNCODE': 'NEW',  # Matches query criteria
            'MESSAGEPAYLOAD': generate_message_payload()
        }
    
    # 80% chance to generate a random record
    return {
        'ORDERKEY': order_key,
        'CORRELIDHEX': uuid.uuid4().hex[:8] + 'hex',
        'ONHOLDFLAG': random.choice(HOLD_FLAGS),
        'TRXNREVN': str(random.randint(1, 5)),
        'TRXNTYPE': random.choice(TRANSACTION_TYPES),
        'DLRCODE': generate_dealer_code(),
        'SRCID': generate_src_id(),
        'TARGETTYPE': random.choice(TARGET_TYPES),
        'MGMTCODE': generate_mgmt_code(),
        'ACTNCODE': random.choice(ACTION_CODES),
        'MESSAGEPAYLOAD': generate_message_payload()
    }

def delivery_report(err, msg):
    if err is not None:
        print(f'Message delivery failed: {err}')
    else:
        print(f'Message delivered to {msg.topic()} [{msg.partition()}] at offset {msg.offset()}')

def validate_env():
    required_vars = [
        'BOOTSTRAP_SERVERS',
        'SCHEMA_REGISTRY_URL',
        'KAFKA_API_KEY',
        'KAFKA_API_SECRET',
        'SR_API_KEY',
        'SR_API_SECRET'
    ]
    
    missing_vars = [var for var in required_vars if not os.getenv(var)]
    
    if missing_vars:
        raise ValueError(
            f"Missing required environment variables: {', '.join(missing_vars)}\n"
            f"Please create a .env file based on .env.template"
        )

def main():
    # Schema Registry configuration
    schema_registry_conf = {
        'url': SCHEMA_REGISTRY_URL,
        'basic.auth.user.info': f'{SR_API_KEY}:{SR_API_SECRET}'
    }
    schema_registry_client = SchemaRegistryClient(schema_registry_conf)

    # Create Avro Serializers for both key and value
    key_schema_str = json.dumps({
        "type": "string"
    })
    
    key_serializer = AvroSerializer(
        schema_registry_client=schema_registry_client,
        schema_str=key_schema_str,
        to_dict=lambda x, ctx: x
    )
    
    value_serializer = AvroSerializer(
        schema_registry_client=schema_registry_client,
        schema_str=json.dumps(value_schema),
        to_dict=lambda x, ctx: x
    )

    # Producer configuration
    producer_conf = {
        'bootstrap.servers': BOOTSTRAP_SERVERS,
        'security.protocol': 'SASL_SSL',
        'sasl.mechanisms': 'PLAIN',
        'sasl.username': KAFKA_API_KEY,
        'sasl.password': KAFKA_API_SECRET,
        'key.serializer': key_serializer,
        'value.serializer': value_serializer,
    }

    # Create Producer instance
    producer = SerializingProducer(producer_conf)

    messages_sent = 0
    start_time = time.time()
    
    try:
        while True:
            record = generate_record()
            key = record['ORDERKEY']
            
            producer.produce(
                topic=TOPIC,
                key=key,
                value=record,
                on_delivery=delivery_report
            )
            
            producer.poll(0)  # Trigger message delivery
            
            messages_sent += 1
            current_time = time.time()
            elapsed_time = current_time - start_time
            
            if elapsed_time >= 60:  # Every minute
                rate = messages_sent / elapsed_time
                print(f'Current production rate: {rate:.2f} messages/second')
                messages_sent = 0
                start_time = current_time
            
            time.sleep(SLEEP_TIME)
            
    except KeyboardInterrupt:
        print('Shutting down producer...')
    finally:
        producer.flush()

# Add validation call before main()
if __name__ == '__main__':
    validate_env()
    main()
