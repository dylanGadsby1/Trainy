// Decides what a change in a train's state is worth telling the user.
// The same rules and wording as TrainAlerts.swift, which does this when there is no server.

import { delay } from "./time.js";
import { departureAt } from "./darwin.js";

/** A delay is reported again once it has moved this many minutes from the last report. */
const DELAY_STEP = 5;

const isKnown = (platform) => Boolean(platform) && platform !== "TBC";

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

  // A platform is only worth an alert while the train can still be caught
  if (next.platform !== old.platform && isKnown(next.platform) && !hasLeft) {
    result.alerts.push({
      kind: "platform",
      body: isKnown(old.platform)
        ? `Platform changed to ${next.platform} (was ${old.platform}).`
        : `Leaves from platform ${next.platform}.`,
    });
  }

  return result;
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
