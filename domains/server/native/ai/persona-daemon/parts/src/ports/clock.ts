export interface ClockPort {
  /** Current time in unix milliseconds. */
  now(): number;
}
