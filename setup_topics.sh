#! /bin/bash

confluent kafka topic list --output json | jq -r '.[].name' | grep '^orders_' | xargs -I {} confluent kafka topic delete "{}" --force

confluent kafka topic create orders_topic

confluent kafka topic create orders_topic_composite

confluent kafka topic create orders_onhold_queryable

