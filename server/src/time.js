// Darwin's clock times are UK local time, wherever the server runs.

/** "HH:mm" if `value` is a clock time, otherwise null ("On time", "Delayed", null…). */
export function clock(value) {
  if (typeof value !== "string") return null;
  const text = value.replace(/[^0-9:]/g, "");
  return /^([01]\d|2[0-3]):[0-5]\d$/.test(text) ? text : null;
}

/** Minutes since midnight for a clock time, or null. */
export function minutes(value) {
  const text = clock(value);
  return text ? Number(text.slice(0, 2)) * 60 + Number(text.slice(3)) : null;
}

/** Minutes late, never negative. Handles a delay that runs past midnight. */
export function delay(scheduled, expected) {
  const from = minutes(scheduled), to = minutes(expected);
  if (from === null || to === null) return 0;
  const late = (to - from + 1440) % 1440;
  return late > 720 ? 0 : late;
}

/** True when Darwin reports a delay but has no new time yet. */
export function isDelayedWithoutEstimate(value) {
  return typeof value === "string" && value.toLowerCase() === "delayed";
}

/** How many minutes UK time is ahead of UTC at `instant`. */
function londonOffsetMinutes(instant) {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/London", hourCycle: "h23",
    year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit",
  }).formatToParts(instant);
  const part = (type) => Number(parts.find((p) => p.type === type).value);
  const wall = Date.UTC(part("year"), part("month") - 1, part("day"), part("hour"), part("minute"));
  return Math.round((wall - instant.getTime()) / 60000);
}

/** The instant of a UK wall-clock time: `day` is "yyyy-MM-dd", `time` is "HH:mm". */
export function londonDate(day, time) {
  const [year, month, date] = day.split("-").map(Number);
  const guess = new Date(Date.UTC(year, month - 1, date, 0, minutes(time) ?? 0));
  return new Date(guess.getTime() - londonOffsetMinutes(guess) * 60000);
}
