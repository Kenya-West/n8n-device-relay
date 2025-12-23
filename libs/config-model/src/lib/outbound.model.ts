import type { DataType, DeviceId, EndpointId, RecipientId, TemplateId } from './config.model';

/**
 * Unique identifier for one planned outbound dispatch (optional but useful for tracing).
 * You can generate it at runtime (UUID, `${eventId}:${i}`, etc).
 */
export type OutboundDispatchId = string;

/**
 * One "unit of work" for later HTTP request building:
 * - pick EndpointModel by endpointId
 * - pick TemplateModel by templateId
 * - pick RecipientModel by recipientId
 *
 * Contains only ids (and optional rule ids for traceability).
 */
export interface OutboundDispatchEntry {
  id?: OutboundDispatchId;

  recipientId: RecipientId;
  endpointId: EndpointId;
  templateId: TemplateId;

  /**
   * Optional: for debugging/traceability only.
   * If you match multiple rules per recipient, include them here.
   */
  matchedRuleIds?: string[];
}

/**
 * Output of your business logic for a single incoming event.
 * This is what your n8n “filtering / routing” Code node should emit.
 */
export interface OutboundDispatchPlan {
  /** WebhookEvent.id (client-side UUID recommended) */
  eventId: string;

  /** WebhookEvent.deviceId */
  deviceId: DeviceId;

  /** WebhookEvent.data.type */
  dataType: DataType;

  /** Optional: ConfigModel.version (helps debugging deployments) */
  configVersion?: string;

  /**
   * Fully expanded list of dispatches.
   * If you want “all possible entries”, this is usually the cartesian result
   * after your selection logic (recipient × endpoint × template), or whatever
   * your business logic decided.
   */
  dispatches: OutboundDispatchEntry[];
}