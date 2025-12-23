import { z } from 'zod';
import { ConfigModel } from './config.model';

export const ConfigSchema = z.object({
  recipients: z.record(
    z.string(),
    z.object({
      id: z.string().min(1),
      vars: z.record(z.string(), z.string()).default({})
    })
  ),
  endpoints: z.record(
    z.string(),
    z.object({
      id: z.string().min(1),
      url: z.url(),
      method: z.enum(['GET', 'POST', 'PUT', 'PATCH', 'DELETE']).default('POST')
    })
  )
});

export type Config = z.infer<typeof ConfigSchema>;

export function parseConfig(input: ConfigModel): Config {
  return ConfigSchema.parse(input);
}

export const SmsReceivedDataSchema = z.object({
  type: z.literal('sms_received'),
  fromName: z.string().optional(),
  fromPhoneNumber: z.string().optional(),
  body: z.string(),
  receivedAt: z.string(),
  simSlot: z.number().int().optional(),
  carrier: z.string().optional(),
  serviceCenter: z.string().optional(),
  isOtp: z.boolean().optional(),
  otpCodes: z.array(z.string()).optional(),
  threadId: z.string().optional(),
  capturedByPackage: z.string().optional(),
  tags: z.array(z.string()).optional(),
});

export const CallReceivedDataSchema = z.object({
  type: z.literal('call_received'),
  from: z.string(),
  startedAt: z.string().optional(),
  endedAt: z.string().optional(),
  direction: z.enum(['incoming', 'outgoing']).optional(),
  missed: z.boolean().optional(),
  rejected: z.boolean().optional(),
  answered: z.boolean().optional(),
  durationSec: z.number().optional(),
  simSlot: z.number().int().optional(),
  carrier: z.string().optional(),
  contactName: z.string().optional(),
  spamLabel: z.string().optional(),
  tags: z.array(z.string()).optional(),
});

export const WifiConnectedDataSchema = z.object({
  type: z.literal('wifi_connected'),
  ssid: z.string(),
  bssid: z.string().optional(),
  ipAddress: z.string().optional(),
  linkSpeedMbps: z.number().optional(),
  rssiDbm: z.number().optional(),
  frequencyMhz: z.number().optional(),
  connectedAt: z.string().optional(),
  security: z
    .enum(['open', 'wep', 'wpa', 'wpa2', 'wpa3', 'unknown'])
    .optional(),
  metered: z.boolean().optional(),
  tags: z.array(z.string()).optional(),
});

export const IncomingDataSchema = z.discriminatedUnion('type', [
  SmsReceivedDataSchema,
  CallReceivedDataSchema,
  WifiConnectedDataSchema,
]);

export type IncomingDataFromSchema = z.infer<typeof IncomingDataSchema>;