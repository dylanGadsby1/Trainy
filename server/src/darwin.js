// Reads a train's live state from National Rail's Darwin departure boards.
// Mirrors DarwinService.refreshed and DarwinServiceAdapter.apply in the app.

import { clock, delay, isDelayedWithoutEstimate, londonDate } from "./time.js";

export const DARWIN_BASE = "https://api1.raildata.org.uk/1010-live-departure-board-dep1_2/LDBWS/api/20220120";

/** Darwin only accepts a time offset of up to two hours either side of now. */
const MAX_OFFSET = 119;
/** A board can start 119 minutes from now and covers the two hours after that. */
const MAX_REACH = MAX_OFFSET + 119;

/** When the train is timetabled to leave the user's station. */
export function departureAt(train) {
  return londonDate(train.departureDate, train.scheduledDeparture);
}

/** The board offset to ask for, or null while Darwin does not list the train. */
export function boardOffset(train, now) {
  const untilDeparture = Math.floor((departureAt(train) - now) / 60000);
  if (untilDeparture < -180 || untilDeparture > MAX_REACH) return null;
  // Start the window half an hour early so a retimed train is still inside it
  return Math.min(Math.max(untilDeparture - 30, -MAX_OFFSET), MAX_OFFSET);
}

/** The origin's departure board, filtered to trains calling at the destination. */
export function boardURL(origin, destination, offset) {
  const url = new URL(`${DARWIN_BASE}/GetDepBoardWithDetails/${origin.toUpperCase()}`);
  url.searchParams.set("numRows", "150");
  url.searchParams.set("filterCrs", destination.toUpperCase());
  url.searchParams.set("filterType", "to");
  if (offset !== 0) url.searchParams.set("timeOffset", String(offset));
  return url.toString();
}

function stopAt(service, crs) {
  return (service.subsequentCallingPoints ?? [])
    .flatMap((group) => group.callingPoint ?? [])
    .find((point) => point.crs === crs);
}

/** The board entry for `train`: by its Darwin id, or failing that by its timetable. */
export function findService(board, train) {
  const services = board?.trainServices ?? [];
  return services.find((service) => train.serviceID && service.serviceID === train.serviceID)
    ?? services.find((service) => {
      if (clock(service.std) !== train.scheduledDeparture) return false;
      // Two trains can leave in the same minute, so one more detail has to agree
      const arrival = clock(stopAt(service, train.destination)?.st);
      return (train.scheduledArrival && train.scheduledArrival === arrival)
        || (train.operatorCode != null && train.operatorCode === service.operatorCode);
    });
}

/** The train's live state, as the app's Live Activity and alerts understand it. */
export function stateFrom(service, train, previous = {}) {
  const stop = stopAt(service, train.destination);
  const expectedDeparture = clock(service.etd) ?? clock(service.std) ?? train.scheduledDeparture;
  const scheduledArrival = clock(stop?.st) ?? train.scheduledArrival ?? null;
  const expectedArrival = clock(stop?.at ?? stop?.et) ?? scheduledArrival;
  const hasArrived = stop?.at != null;

  const departureDelay = delay(train.scheduledDeparture, expectedDeparture);
  const arrivalDelay = delay(scheduledArrival, expectedArrival);

  return {
    expectedDeparture,
    expectedArrival,
    // Darwin withdraws the platform once a train has left, so keep the last one seen
    platform: service.platform ?? previous.platform ?? "TBC",
    // A platform on the board is live; one the app sent can be the timetable's plan
    platformConfirmed: service.platform != null || (previous.platformConfirmed ?? false),
    delayMinutes: hasArrived ? arrivalDelay : Math.max(departureDelay, arrivalDelay),
    isCancelled: service.isCancelled === true || service.filterLocationCancelled === true || stop?.isCancelled === true,
    hasUnknownDelay: isDelayedWithoutEstimate(service.etd) || isDelayedWithoutEstimate(stop?.et),
    hasArrived,
  };
}
