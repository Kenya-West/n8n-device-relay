import { EndpointId, EndpointModel } from "./config.model";
import { OtlpLogsExportRequest } from "./otlp-request.model";

export interface LogIngestionModel {
    name?: string;
    disabled?: boolean;
    type: "open-telemetry";
    rules: LogRuleModel[];
    payloads: OpenTelemetryLogIngestionPayload[];
    endpoints: Record<EndpointId, EndpointModel>;
}

export enum Step {
    INITIAL = "initial",
    CONFIG_VALIDATED = "config_validated",
    VALIDATE_TOKENS_LENGTH = "validate_tokens_length",
    VALIDATE_CONFIG_TOKEN = "validate_config_token",
    VALIDATE_DEVICE_TOKEN = "validate_device_token",
    VALIDATE_DEBUG_TOKEN = "validate_debug_token",
    VALIDATE_DATA_TYPE = "validate_data_type",
    VALIDATE_DEVICE_ID = "validate_device_id",
    STEP_REMAP_OBJECTS = "step_remap_objects",
    STEP_FILTER_RECIPIENTS_BY_DEVICEID_DATATYPE = "step_filter_recipients_by_deviceid_datatype",
    STEP_FILTER_RECIPIENTS_BY_RULES = "step_filter_recipients_by_rules",
    STEP_FILTER_RECIPIENTS_BY_ENDPOINTIDS_TEMPLATEIDS = "step_filter_recipients_by_endpointids_templateids",
    STEP_FORM_OUTBOUND = "step_form_outbound",
    STEP_COMPOSE_MESSAGES = "step_compose_messages",
    STEP_TEMPLATE_MESSAGES = "step_template_messages",
    SEND_MESSAGE = "send_message",
    SEND_MESSAGE_AFTER = "send_message_after"
}

export interface OpenTelemetryLogIngestionPayload {
    id: string;
    body: OtlpLogsExportRequest;
}

/**
 * A rule evaluated in order; first match wins (typical policy).
 */
export interface LogRuleModel {
  /** Unique id of the rule (for UI, debugging, and test referencing). */
  id: string;

  /** Optional human description. */
  description?: string;
  /**
   * Conditions to match.
   */
  steps: Step[];
  /** Unique ids of the payloads to use when this rule matches. */
  payloadIds: string[];
  endpointIds: EndpointId[];
}