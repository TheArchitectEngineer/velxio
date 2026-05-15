/**
 * Phase 1b continued — Step 1 tests for MixedModeScheduler.
 *
 * Exercises the subscriber routing and voltage cache in isolation from
 * the SPICE engine.  The engine is never booted in these tests; we
 * drive `publishVoltage` directly so the routing logic can be locked
 * down before the real `alter + tran + readVec` loop lands.
 *
 * Coverage:
 *   - publishVoltage fires every matching subscriber and only those
 *   - getCurrentVoltage returns the last published value per pin
 *   - unsubscribe removes the callback cleanly
 *   - reset (via __resetMixedModeScheduler) clears state between tests
 */
import { describe, it, expect, vi, afterEach } from 'vitest';
import {
  getMixedModeScheduler,
  __resetMixedModeScheduler,
} from '../simulation/spice/MixedModeScheduler';

afterEach(() => {
  __resetMixedModeScheduler();
});

describe('MixedModeScheduler — voltage cache', () => {
  it('returns null until something is published', () => {
    const sched = getMixedModeScheduler();
    expect(sched.getCurrentVoltage('q1', 'C')).toBeNull();
  });

  it('returns the last published voltage per (component, pin)', () => {
    const sched = getMixedModeScheduler();
    sched.publishVoltage('q1', 'C', 4.5);
    sched.publishVoltage('q1', 'B', 1.2);
    sched.publishVoltage('q2', 'C', 0.3);
    expect(sched.getCurrentVoltage('q1', 'C')).toBe(4.5);
    expect(sched.getCurrentVoltage('q1', 'B')).toBe(1.2);
    expect(sched.getCurrentVoltage('q2', 'C')).toBe(0.3);
    sched.publishVoltage('q1', 'C', 2.7); // overwrite
    expect(sched.getCurrentVoltage('q1', 'C')).toBe(2.7);
  });
});

describe('MixedModeScheduler — subscribe / publish routing', () => {
  it('fires the matching subscriber with the published voltage', () => {
    const sched = getMixedModeScheduler();
    const cb = vi.fn();
    sched.subscribe('q1', 'C', cb);
    sched.publishVoltage('q1', 'C', 4.7);
    expect(cb).toHaveBeenCalledTimes(1);
    expect(cb).toHaveBeenCalledWith('UNKNOWN', 4.7);
  });

  it('does NOT fire subscribers watching a different pin', () => {
    const sched = getMixedModeScheduler();
    const cbMatching = vi.fn();
    const cbOtherPin = vi.fn();
    const cbOtherComp = vi.fn();
    sched.subscribe('q1', 'C', cbMatching);
    sched.subscribe('q1', 'B', cbOtherPin);
    sched.subscribe('q2', 'C', cbOtherComp);
    sched.publishVoltage('q1', 'C', 4.7);
    expect(cbMatching).toHaveBeenCalledTimes(1);
    expect(cbOtherPin).not.toHaveBeenCalled();
    expect(cbOtherComp).not.toHaveBeenCalled();
  });

  it('supports multiple subscribers on the same pin (fan-out)', () => {
    const sched = getMixedModeScheduler();
    const cbA = vi.fn();
    const cbB = vi.fn();
    sched.subscribe('q1', 'C', cbA);
    sched.subscribe('q1', 'C', cbB);
    sched.publishVoltage('q1', 'C', 4.7);
    expect(cbA).toHaveBeenCalledWith('UNKNOWN', 4.7);
    expect(cbB).toHaveBeenCalledWith('UNKNOWN', 4.7);
  });

  it('unsubscribe handle detaches the callback', () => {
    const sched = getMixedModeScheduler();
    const cb = vi.fn();
    const cancel = sched.subscribe('q1', 'C', cb);
    sched.publishVoltage('q1', 'C', 4.7);
    expect(cb).toHaveBeenCalledTimes(1);
    cancel();
    sched.publishVoltage('q1', 'C', 0.3);
    expect(cb).toHaveBeenCalledTimes(1); // not called again
  });

  it('reset clears subscribers and voltage cache', () => {
    const sched = getMixedModeScheduler();
    const cb = vi.fn();
    sched.subscribe('q1', 'C', cb);
    sched.publishVoltage('q1', 'C', 4.7);
    __resetMixedModeScheduler();

    const sched2 = getMixedModeScheduler();
    expect(sched2).not.toBe(sched);
    expect(sched2.getCurrentVoltage('q1', 'C')).toBeNull();
    sched2.publishVoltage('q1', 'C', 0.5);
    // The old subscriber attached to the disposed scheduler must NOT
    // fire from the new scheduler instance.
    expect(cb).toHaveBeenCalledTimes(1);
  });
});
