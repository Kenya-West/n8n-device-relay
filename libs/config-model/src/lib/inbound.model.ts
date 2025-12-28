import { DeviceId } from "./config.model";

/**
 * Supported incoming data types.
 */
export type DataType = "sms_received" | "call_received" | "wifi_connected";

/**
 * Envelope for webhook input to n8n.
 * This is what your automation app should POST to n8n.
 */
export interface WebhookEvent {
  /** Unique id for the event (client-side UUID recommended). */
  id: string;

  /** When the event was created on the device (ISO 8601 preferred). */
  createdAt: string;

  /**
   * Optional source app identifier (tasker/macrodroid/automate/custom).
   * Useful for debugging and metrics.
   */
  source?: "tasker" | "macrodroid" | "automate" | "other";

  /**
   * Optional raw metadata for debugging.
   * Keep small to avoid accidental sensitive data.
   */
  meta?: Record<string, string | number | boolean | null>;
  /** Device data */
  device?: DeviceDataModel;
  /** The actual business payload. */
  data: InboundDataModel;
}

export interface DeviceDataModel {
  /** Which device produced the event. */
  id: DeviceId;
  // battery
  batteryLevelPercent?: number;
  isCharging?: boolean;
  // SIM / cellular
  simSlotCount?: number;
  isEsimPresent?: boolean;
  currentSimSlotIndex?: number;
  isCurrentEsim?: boolean;
  cellularCarrierName?: string;
  // location
  locationLatitude?: number;
  locationLongitude?: number;
  locationPoint?: string;
  locationLink?: string;
  locationLastTimestamp?: string;
  locationAccuracyMeters?: number;
  currentSpeed?: number;
  // Wi-Fi
  currentWifiSsid?: string;
  currentWifiBssid?: string;
  // network common status
  networkType?: "wifi" | "cellular" | "none" | "unknown";
  // screen
  isScreenOn?: boolean;
  // volume
  mediaVolumePercent?: number;
  ringerVolumePercent?: number;
  // bluetooth
  isBluetoothOn?: boolean;
  // Do Not Disturb
  isDoNotDisturbOn?: boolean;
  // airplane mode
  isAirplaneModeOn?: boolean;
  // time zone
  timeZone?: string;
  // locale
  locale?: string;
  // storage
  availableStorageBytes?: number;
  totalStorageBytes?: number;
  // features
  hasNfc?: boolean;
  hasFingerprintSensor?: boolean;
}

/**
 * Discriminated union over `data.type`.
 * Each variant defines fields that are realistic for Android automation captures.
 */
export type InboundDataModel = SmsReceivedDataModel | CallReceivedDataModel | WifiConnectedDataModel | AppNotificationDataModel;

/**
 * Payload for "sms_received".
 */
export interface SmsReceivedDataModel {
  /** Discriminator. */
  type: "sms_received";

  /** Sender address/number (may be alphanumeric in some regions). */
  fromName?: string;
  fromNameInContacts?: string;
  fromPhoneNumber?: string;

  /** Message body text. */
  body: string;

  /** ISO 8601 timestamp when SMS was received (device time). */
  at?: string;

  /** SIM slot index if known (1/2). */
  simSlot?: number;

  /** Subscription/carrier name if available. */
  carrier?: string;

  /** Message center address if captured. */
  serviceCenter?: string;

  /** True if message looks like OTP (if your automation tags it). */
  isOtp?: boolean;

  /** Extracted OTP code(s) if automation parses it. */
  otpCodes?: string[];

  /** Optional thread id / conversation id from SMS provider. */
  threadId?: string;

  /** Optional app/package that captured the SMS (some automations rely on notifications). */
  capturedByPackage?: string;

  /** Optional keyword tags computed by automation app. */
  tags?: string[];
}

/**
 * Payload for "call_received" (incoming call).
 */
export interface CallReceivedDataModel {
  /** Discriminator. */
  type: "call_received";

  /** Sender address/number (may be alphanumeric in some regions). */
  fromName?: string;
  fromNameInContacts?: string;
  fromPhoneNumber?: string;

  /** ISO 8601 timestamp when SMS was received (device time). */
  at?: string;

  /** ISO 8601 timestamp when call ended (if known). */
  endedAt?: string;

  /** Call direction. For your type this is typically "incoming" but allow future reuse. */
  direction?: "incoming" | "outgoing";

  /** Call was missed (never answered). */
  missed?: boolean;

  /** Call was rejected/declined. */
  rejected?: boolean;

  /** Answered flag (mutually exclusive with missed/rejected in typical data). */
  answered?: boolean;

  /** Duration in seconds if endedAt known. */
  durationSec?: number;

  /** SIM slot index if known. */
  simSlot?: number;

  /** Carrier/subscription name if available. */
  carrier?: string;

  /** Contact name if resolved by device. */
  contactName?: string;

  /** Spam / suspected spam label if provided by dialer/automation. */
  spamLabel?: string;

  /** Optional keyword tags computed by automation app. */
  tags?: string[];
}

/**
 * Payload for "wifi_connected".
 */
export interface WifiConnectedDataModel {
  /** Discriminator. */
  type: "wifi_connected";

  /** SSID network name (human-readable). */
  ssid: string;

  /** BSSID / AP MAC address if available. */
  bssid?: string;

  /** Device IP address (local) if available. */
  ipAddress?: string;

  /** Link speed in Mbps if available. */
  linkSpeedMbps?: number;

  /** RSSI signal strength in dBm if available. */
  rssiDbm?: number;

  /** Frequency in MHz if available. */
  frequencyMhz?: number;

  /** ISO 8601 timestamp when SMS was received (device time). */
  at?: string;

  /** Network security type if automation can detect. */
  security?: "open" | "wep" | "wpa" | "wpa2" | "wpa3" | "unknown";

  /** Whether device considers this metered. */
  metered?: boolean;

  /** Optional keyword tags computed by automation app. */
  tags?: string[];
}

export interface AppNotificationDataModel {
  /** Discriminator. */
  type: "notification_received";
  /** Package name of app sending the notification. */
  packageName: string;
  /** App name if available. */
  appName?: string;
  /** ISO 8601 timestamp when SMS was received (device time). */
  at?: string;
  /** Notification title if available. */
  title?: string;
  /** Notification body text if available. */
  body?: string;
  /** Optional keyword tags computed by automation app. */
  tags?: string[];
}