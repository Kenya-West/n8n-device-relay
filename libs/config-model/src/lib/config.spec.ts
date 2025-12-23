import { describe, expect, it } from 'vitest';
import { ConfigSchema, parseConfig } from './config.schema';
import { configModels } from '../test/config.mock.json';
import { ConfigModel } from './config.model';

describe('ConfigSchema', () => {
  it('accepts a valid config', () => {
    const input = configModels.minimal as ConfigModel;

    const result = ConfigSchema.safeParse(input);
    expect(result.success).toBe(true);

    // parseConfig returns typed Config
    expect(parseConfig(input).recipients['alice'].id).toBe('alice');
  });

  it('rejects invalid url', () => {
    const bad = configModels.minimal as ConfigModel;
    bad.endpoints["telegram-default"].url = "not-a-url";

    const result = ConfigSchema.safeParse(bad);
    expect(result.success).toBe(false);

    if (!result.success) {
      // Useful for debugging failure shape
      expect(result.error.issues[0].path).toContain('url');
    }
  });

  it('fills defaults', () => {
    const input = configModels.minimal as ConfigModel;

    const parsed = parseConfig(input);
    expect(parsed.recipients["a"].vars).toEqual({});
    expect(parsed.endpoints["tg"].method).toBe('POST');
  });
});
