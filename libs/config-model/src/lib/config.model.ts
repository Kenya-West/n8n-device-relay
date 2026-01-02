import { DataType, InboundDataModel } from "./inbound.model";
import { LogIngestionModel } from "./log.model";

 

/**
 * Core configuration for an n8n workflow that:
 * - receives "data" from an automation app via webhook
 * - selects recipients & templates
 * - renders messages (templating)
 * - sends to external HTTP endpoints (e.g., Telegram Bot API)
 *
 * All top-level entities are objects (maps) keyed by id to match your preference
 * (objects over arrays) and enable stable lookups in n8n.
 */
export interface ConfigModel {
  /** Schema version for migrations and backward compatibility. */
  version: string;
  tokens: Record<string, string>[];

  /** Optional human label for the configuration instance. */
  name?: string;

  /**
   * A map of recipients by `id`.
   *
   * Key MUST match `Recipient.id`.
   */
  recipients: Record<RecipientId, RecipientModel>;

  /**
   * A map of endpoints by `id`.
   *
   * Endpoints may reference `{recipient.*}` placeholders.
   */
  endpoints: Record<EndpointId, EndpointModel>;

  /**
   * A map of templates by `id`.
   *
   * Templates may reference placeholders from data/recipient/meta.
   */
  templates: Record<TemplateId, TemplateModel>;

  /**
   * Optional device registry. If omitted, "device checks" can rely solely on deviceId
   * strings embedded in incoming payloads and recipients.allowedDeviceIds.
   */
  devices?: Record<DeviceId, DeviceDefinition>;

  logIngestions?: Record<LogIngestionId, LogIngestionModel>;

  /**
   * Optional global defaults applied by n8n when building outbound requests.
   * Per-endpoint settings override these defaults.
   */
  defaults?: {
    /** Default timeout in milliseconds for outbound HTTP calls. */
    httpTimeoutMs?: number;

    /** Default headers applied to outbound HTTP calls unless overridden. */
    headers?: Record<string, string>;

    /**
     * If true, the system should reject any placeholder that cannot be resolved
     * (fail-fast). If false, unresolved placeholders may be left as-is or replaced
     * with empty string depending on runtime policy.
     */
    strictTemplating?: boolean;
  };
}

/* ----------------------------- IDs / Aliases ----------------------------- */

export type RecipientId = string;
export type EndpointId = string;
export type TemplateId = string;
export type DeviceId = string;
export type LogIngestionId = string;

/* -------------------------------- Recipient ------------------------------ */

/**
 * A "recipient" is a business-logic target that receives templated messages via one
 * or more endpoints. Example: a Telegram user/channel/chat ID plus extra vars.
 */
export interface RecipientModel {
  /** Optional display name for UI or logs. */
  name?: string;
  disabled?: boolean;

  /**
   * Recipient-scoped variables for templating, e.g.:
   * { "tgChatId": "123456", "lang": "ru", "timezone": "Asia/Bangkok" }
   *
   * Use `{recipient.vars.tgChatId}` (or `{recipient.vars.lang}`) in templates/endpoints.
   */
  vars: Record<string, string | number | boolean | null>;

  /**
   * Which incoming devices are allowed to trigger messages to this recipient.
   * If omitted or empty, all devices are allowed (unless your runtime enforces otherwise).
   */
  allowedDeviceIds?: DeviceId[];

  /**
   * Which endpoint(s) the recipient is eligible to send through.
   * If omitted or empty, runtime may allow all endpoints or require explicit mapping
   * depending on your policy.
   */
  endpointIds?: EndpointId[];

  /**
   * Which template(s) may be used for this recipient.
   * If omitted or empty, runtime may allow all templates or require explicit mapping
   * depending on your policy.
   */
  templateIds?: TemplateId[];

  /**
   * Optional filtering by data types for this recipient.
   * If omitted, all data types are allowed.
   */
  allowedDataTypes?: DataType[];

  /**
   * Optional per-recipient rendering preferences.
   * Useful for future UI and consistent formatting.
   */
  rendering?: {
    /** Language preference for template selection, if you implement i18n. */
    language?: string;

    /** Timezone for formatting timestamps. */
    timezone?: string;

    /** If true, escape HTML (Telegram HTML mode) or perform endpoint-specific escaping. */
    escapeMode?: "none" | "telegram_html" | "telegram_markdownv2";
  };

  /**
   * Optional "routing rules" to select specific template(s) and/or endpoint(s)
   * based on incoming data. This enables business logic in config instead of n8n code.
   */
  rules: RecipientRuleModel[];
}

/**
 * A rule evaluated in order; first match wins (typical policy).
 */
export interface RecipientRuleModel {
  /** Unique id of the rule (for UI, debugging, and test referencing). */
  id: string;

  /** Optional human description. */
  description?: string;
  type: DataType;

  /** Match conditions; all specified conditions must match (AND). */
  when: FieldPredicate[];

  /**
   * Actions to apply when the rule matches.
   * These override or constrain the recipient's default templateIds/endpointIds.
   */
  then: {
    /** Use these templates (in order). */
    templateIds?: TemplateId[];

    /** Send via these endpoints (in order). */
    endpointIds?: EndpointId[];
  };
}

/**
 * A simple field predicate for config-driven routing.
 */
export interface FieldPredicate {
  /** Path in the runtime object (you define actual resolver). */
  path: string;

  /** Comparison operator. */
  operator:
    | "equals"
    | "not_equals"
    | "includes"
    | "not_includes"
    | "starts_with"
    | "ends_with"
    | "matches_regex"
    | "gt"
    | "gte"
    | "lt"
    | "lte"
    | "exists";

  /** Comparison value; omitted for `exists`. */
  value?: string | number | boolean | null;
}

/* -------------------------------- Endpoint -------------------------------- */

/**
 * Defines how to send an HTTP request.
 * URLs, headers, query, and body may include `{recipient.*}` placeholders.
 *
 * NOTE: Actual auth secrets should ideally NOT be embedded directly here unless
 * encrypted or stored in n8n credentials; model allows it for completeness.
 */
export interface EndpointModel {
  /** Optional display name for UI or logs. */
  name?: string;

  /** HTTP method. */
  method: HttpMethod;

  /**
   * Fully qualified URL including path.
   * May contain templated placeholders from recipient vars, e.g.:
   *   "https://api.telegram.org/bot{recipient.vars.botToken}/sendMessage"
   */
  url: string;

  /**
   * Optional query string parameters.
   * Values may include placeholders.
   */
  searchParams?: Record<string, string>;

  /**
   * Optional headers.
   * Values may include placeholders.
   */
  headers?: Record<string, string>;

  /**
   * Optional request body settings.
   * If not provided, runtime can send no body.
   */
  body?: EndpointBody;

  /**
   * Timeout in milliseconds for this endpoint call.
   * Overrides config.defaults.httpTimeoutMs.
   */
  timeoutMs?: number;

  /**
   * Optional retry policy for transient failures.
   */
  retry?: {
    /** Maximum attempts including the first try. */
    maxAttempts: number;
    /** Backoff strategy. */
    backoff: "fixed" | "exponential";
    /** Base delay in milliseconds. */
    baseDelayMs: number;
    /** Only retry on these HTTP status codes, if specified. */
    retryOnStatusCodes?: number[];
  };

  /**
   * Optional expectation/validation on response for success determination.
   * Useful for endpoints like Telegram that always return JSON with ok=true/false.
   */
  successCriteria?: {
    /** Treat these status codes as success. If omitted, use 200-299. */
    statusCodes?: number[];
    /**
     * A JSON path to a boolean "success" field.
     * Example for Telegram: "ok"
     */
    jsonBooleanPath?: string;
  };
}

export type HttpMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";

export interface EndpointBody {
  /**
   * Body format.
   * - json: typical REST payload
   * - form_urlencoded: Telegram often supports application/x-www-form-urlencoded
   * - raw: string payload (e.g., pre-rendered JSON or text)
   */
  type: "json" | "form_urlencoded" | "raw";

  /**
   * Body content.
   * - For json/form_urlencoded: object where leaf values may contain placeholders
   * - For raw: a string which may contain placeholders
   */
  content: Record<string, unknown> | string;
}

/* -------------------------------- Templates ------------------------------- */

/**
 * A template is a named message payload with placeholders.
 * You can keep it generic, or add endpoint-specific "rendering targets" later.
 */
export interface TemplateModel {
  /** Optional human name for UI/logs. */
  name?: string;

  /**
   * Main template string. Placeholders use `{...}` and are resolved at runtime.
   *
   * Recommended placeholder namespaces:
   * - {data.*}      incoming data payload fields
   * - {recipient.*} recipient fields/vars
   * - {meta.*}      envelope info (deviceId, receivedAt, etc.)
   */
  text: string;

  /**
   * Optional endpoint-specific formatting metadata.
   * Example: Telegram sendMessage parse_mode.
   */
  format?: {
    /** Controls how the receiving endpoint should parse markup. */
    parseMode?: "plain" | "telegram_html" | "telegram_markdownv2";

    /** If true, strip unknown placeholders (otherwise fail or keep). */
    ignoreUnknownPlaceholders?: boolean;
  };

  /**
   * Optional additional fields that can be used as payload parts
   * (e.g., title, subject, caption), depending on endpoint mapping.
   */
  fields?: Record<string, string>;
}

/* --------------------------------- Devices -------------------------------- */

/**
 * Optional device registry entry to enrich logs and enable per-device gating.
 */
export interface DeviceDefinition {
  /** Optional friendly name. */
  name?: string;

  /** Optional platform description. */
  platform?: "android" | "ios" | "other";

  /** Optional additional metadata. */
  vars?: Record<string, string | number | boolean | null>;
}

/**
 * Utility type: fully rendered outbound HTTP request.
 * Useful for unit tests and for a "config check" web app preview.
 */
export interface RenderedHttpRequest {
  method: HttpMethod;
  url: string;
  headers: Record<string, string>;
  query: Record<string, string>;
  body?: {
    contentType: string;
    payload: unknown;
  };
}
