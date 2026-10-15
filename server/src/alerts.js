// Decides what a change in a train's state is worth telling the user.
// The same rules and wording as TrainAlerts.swift, which does this when there is no server.

import { delay } from "./time.js";
import { departureAt } from "./darwin.js";

/** A delay is reported again once it has moved this many minutes from the last report. */
const DELAY_STEP = 5;

const isKnown = (platform) => Boolean(platform) && platform !== "TBC" && platform !== "–";

/** The platform came from a live feed, not only the timetable. A state saved before this was recorded counts as live. */
const isConfirmed = (state) => isKnown(state.platform) && (state.platformConfirmed ?? true);

/** The reminders before a train leaves: due this many minutes before, and not sent once it is `until` or less. */
const REMINDERS = [
  { kind: "hour", minutes: 60, until: 55 },
  { kind: "soon", minutes: 5, until: 2 },
];

/** "20:05 Milton Keynes Central to London Euston" */
export function journeyName(train) {
  return `${train.scheduledDeparture} ${train.originName ?? train.origin} to ${train.destinationName ?? train.destination}`;
}

/** When the train is now expected to leave the user's station. */
function expectedDepartureAt(train, state) {
  const late = delay(train.scheduledDeparture, state.expectedDeparture);
  return new Date(departureAt(train).getTime() + late * 60000);
}

/**
 * Compares a train's state before and after a check.
 * Returns the alerts to send and the delay the user has now been told about.
 */
export function changes(train, old, next, now) {
  const result = { alerts: [], alertedDelay: train.alertedDelay ?? old.delayMinutes ?? 0 };
  if (next.hasArrived) return result;

  if (next.isCancelled) {
    if (!old.isCancelled) result.alerts.push({ kind: "delay", body: "This train has been cancelled." });
    return result;
  }

  const hasLeft = expectedDepartureAt(train, next) <= now;

  if (next.hasUnknownDelay) {
    if (!old.hasUnknownDelay) result.alerts.push({ kind: "delay", body: "Delayed. No new time has been given yet." });
  } else if (Math.abs(next.delayMinutes - result.alertedDelay) >= DELAY_STEP) {
    result.alertedDelay = next.delayMinutes;
    let body = "Back on time.";
    if (next.delayMinutes > 0) {
      body = `Running ${next.delayMinutes} min late.`;
      if (!hasLeft && delay(train.scheduledDeparture, next.expectedDeparture) > 0) {
        body += ` Now expected to leave at ${next.expectedDeparture}.`;
      } else if (next.expectedArrival) {
        body += ` Now expected to arrive at ${next.expectedArrival}.`;
      }
    }
    result.alerts.push({ kind: "delay", body });
  }

  // When a live feed first gives the platform, and whenever it changes after that. A platform
  // is only worth an alert while the train can still be caught.
  if (isConfirmed(next) && !hasLeft) {
    let body = null;
    if (isConfirmed(old)) {
      if (next.platform !== old.platform) body = `Platform changed to ${next.platform} (was ${old.platform}).`;
    } else if (isKnown(old.platform) && old.platform !== next.platform) {
      body = `Platform ${next.platform} confirmed. The timetable said ${old.platform}.`;
    } else {
      body = `Platform ${next.platform} confirmed.`;
    }
    if (body) result.alerts.push({ kind: "platform", body });
  }

  return result;
}

/**
 * The reminder due now before `train` leaves, from its latest state, or null.
 * The app schedules the same ones ahead when there is no server.
 */
export function departureReminder(train, now) {
  const state = train.state;
  if (!train.remind || state.isCancelled || state.hasArrived) return null;

  const left = Math.round((expectedDepartureAt(train, state) - now) / 60000);
  const sent = train.reminded ?? [];
  // The latest one whose time has come. Once a later one is sent, those before it are passed over.
  const index = REMINDERS.findLastIndex((reminder) => left <= reminder.minutes);
  const due = REMINDERS[index];
  if (!due || left <= due.until || REMINDERS.slice(index).some((reminder) => sent.includes(reminder.kind))) return null;

  return { kind: due.kind, body: departureBody(train, state, left) };
}

/** "Leaves in 1 hour, at 17:52 (10 min late), from platform 4." The app's words too. */
function departureBody(train, state, minutes) {
  const when = minutes >= 60 ? "1 hour" : `${minutes} minutes`;
  if (state.hasUnknownDelay) return `Due to leave in ${when}, but delayed with no new time yet.`;

  let body = `Leaves in ${when}, at ${state.expectedDeparture}`;
  const late = delay(train.scheduledDeparture, state.expectedDeparture);
  if (late > 0) body += ` (${late} min late)`;
  return body + (isConfirmed(state) ? `, from platform ${state.platform}.` : ". Platform not confirmed yet.");
}

/** What the Live Activity shows: TrainyActivityAttributes.ContentState in the app. */
export function contentState(train, state) {
  return {
    scheduledDeparture: train.scheduledDeparture,
    expectedDeparture: state.expectedDeparture,
    delayMinutes: state.delayMinutes,
    platform: state.platform,
    isCancelled: state.isCancelled,
  };
}
