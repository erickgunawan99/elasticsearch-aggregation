#!/bin/sh
ES="http://elasticsearch:9200"

echo "\n==> Creating index template..."

curl -X PUT "http://localhost:9200/_index_template/metrics-template" \
  -H "Content-Type: application/json" -d '{
  "index_patterns": ["metrics-*"],
  "data_stream": { },
  "template": {
    "settings": { 
      "index.mode": "time_series",
      "index.lifecycle.name": "metrics-policy",
      "index.look_ahead_time": "2h"
    },
    "mappings": {
      "properties": {
        "@timestamp":      { "type": "date"},
        "host":            { "type": "keyword", "time_series_dimension": true },
        "service":         { "type": "keyword", "time_series_dimension": true },
        "cpu_percent":     { "type": "float", "time_series_metric": "gauge" },
        "memory_percent":  { "type": "float", "time_series_metric": "gauge" },
        "latency_ms":      { "type": "float", "time_series_metric": "gauge" },
        "request_count":   { "type": "integer", "time_series_metric": "counter" },
        "error":           { "type": "boolean" }
      }
    }
  }
}'

## create data stream manually
curl -X PUT "http://localhost:9200/_data_stream/metrics-raw"

curl -X POST "http://localhost:9200/_aliases" \
  -H "Content-Type: application/json" -d '{
  "actions": [
    {
      "add": {
        "index": "metrics-raw",
        "alias": "metrics",
        "is_write_index": true
      }
    }
  ]
}'

echo "==> Creating ILM policy..."
curl -s -X PUT "http://localhost:9200/_ilm/policy/metrics-policy" \
  -H "Content-Type: application/json" -d '{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": { "max_age": "1d", "max_primary_shard_size": "5gb" }
        }
      },
      "warm": {
        "min_age": "1d",
        "actions": {
          "downsample": { "fixed_interval": "1h" },
          "readonly": {}
        }
      },
      "cold": {
        "min_age": "7d",
        "actions": {
          "downsample": { "fixed_interval": "1d" }
        }
      },
      "delete": {
        "min_age": "30d",
        "actions": { "delete": {} }
      }
    }
  }
}'

echo "==> Creating continuous transform..."
curl -s -X PUT "http://localhost:9200/_transform/agg_metrics_every5m" \
  -H "Content-Type: application/json" -d '{
  "source": { "index": "metrics-*" },
  "dest":   { "index": "transformed-agg" },
  "frequency": "1m",
  "sync": {
    "time": {
      "field": "@timestamp",
      "delay": "30s"
    }
  },
  "pivot": {
    "group_by": {
      "bucket_5m":    { "date_histogram": { "field": "@timestamp", "fixed_interval": "5m" } }},
    "aggregations": {
      "avg_cpu":       { "avg":         { "field": "cpu_percent" } },
      "avg_memory":    { "avg":         { "field": "memory_percent" } },
      "avg_latency":   { "avg":         { "field": "latency_ms" } },
      "p99_latency":   { "percentiles": { "field": "latency_ms", "percents": [99] } },
      "total_requests":{ "sum":         { "field": "request_count" } },
      "error_true_total":{ "filter":    { "term": { "error": true } } }
    }
  }
}'

echo "==> Starting transform..."
curl -s -X POST "http://localhost:9200/_transform/agg_metrics_every5m/_start"

echo "==> Creating ILM policy for metrics-every5m..."
curl -s -X PUT "http://localhost:9200/_ilm/policy/agg-policy" \
  -H "Content-Type: application/json" -d '{
  "policy": {
    "phases": {
      "delete": {
        "min_age": "10d",
        "actions": { "delete": {} }
      }
    }
  }
}'

echo "==> Attaching ILM to transform index..."
curl -s -X PUT "http://localhost:9200/transformed-agg/_settings" \
  -H "Content-Type: application/json" -d '{
  "index.lifecycle.name": "agg-policy"
}'

echo "\n==> Done. Bootstrap complete."