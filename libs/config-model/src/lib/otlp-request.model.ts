// otlp-logs-types.ts
// Types-only representation of OTLP LogsData (JSON form)

export type OtlpAnyValue =
  | { stringValue: string }
  | { boolValue: boolean }
  | { intValue: string }        // 64-bit integers are represented as strings in JSON
  | { doubleValue: number }
  | { arrayValue: { values: OtlpAnyValue[] } }
  | { kvlistValue: { values: OtlpKeyValue[] } }
  | { bytesValue: string };     // base64-encoded

export interface OtlpKeyValue {
  key: string;
  value: OtlpAnyValue;
}

export interface OtlpInstrumentationScope {
  name?: string;
  version?: string;
  attributes?: OtlpKeyValue[];
  droppedAttributesCount?: number;
}

export interface OtlpResource {
  attributes?: OtlpKeyValue[];
  droppedAttributesCount?: number;
}

export interface OtlpLogRecord {
  timeUnixNano?: string;          // nanoseconds since epoch, as string
  observedTimeUnixNano?: string;  // optional, same format
  severityNumber?: number;        // 1–24 per OTLP enum (TRACE to FATAL)
  severityText?: string;          // e.g. "INFO", "WARN"
  body?: OtlpAnyValue;

  attributes?: OtlpKeyValue[];
  droppedAttributesCount?: number;

  flags?: number;                 // bitmask (e.g. trace flags)

  traceId?: string;               // 16-byte hex-encoded string (32 chars)
  spanId?: string;                // 8-byte hex-encoded string (16 chars)
}

export interface OtlpScopeLogs {
  scope?: OtlpInstrumentationScope;
  logRecords?: OtlpLogRecord[];
  schemaUrl?: string;
}

export interface OtlpResourceLogs {
  resource?: OtlpResource;
  scopeLogs?: OtlpScopeLogs[];
  schemaUrl?: string;
}

// Top-level OTLP LogsData payload (export request)
export interface OtlpLogsExportRequest {
  resourceLogs?: OtlpResourceLogs[];
}
