import { test } from "node:test";
import assert from "node:assert/strict";

import { clock, delay, londonDate } from "../src/time.js";
import { boardOffset, findService, stateFrom } from "../src/darwin.js";
import { changes, contentState } from "../src/alerts.js";

const train = {
  key: "2026-10-13-15:30-MKC-EUS",
  serviceID: "abc",
  origin: "MKC", destination: "EUS",
  originName: "Milton Keynes Central", destinationName: "London Euston",
  departureDate: "2026-10-13", scheduledDeparture: "15:30", scheduledArrival: "16:05",
  operatorCode: "VT",
};

const onTime = {
  expectedDeparture: "15:30", expectedArrival: "16:05", platform: "TBC",
  delayMinutes: 0, isCancelled: false, hasUnknownDelay: false, hasArrived: false,
};

// 15:00 UK time on the day, half an hour before the train
const before = new Date("2026-10-13T14:00:00Z");

test("clock times and status words", () => {
  assert.equal(clock("15:30"), "15:30");
  assert.equal(clock("On time"), null);
  assert.equal(clock("Delayed"), null);
  assert.equal(clock(null), null);
});

test("delay is never negative and survives midnight", () => {
  assert.equal(delay("15:30", "15:42"), 12);
  assert.equal(delay("15:30", "15:28"), 0);
  assert.equal(delay("23:55", "00:10"), 15);
});

test("UK wall-clock times in summer and winter", () => {
  assert.equal(londonDate("2026-10-13", "15:30").toISOString(), "2026-10-13T14:30:00.000Z");
  assert.equal(londonDate("2026-12-01", "15:30").toISOString(), "2026-12-01T15:30:00.000Z");
});

test("Darwin is only asked about trains it lists", () => {
  assert.equal(boardOffset(train, before), 0);
  assert.equal(boardOffset(train, new Date("2026-10-13T08:00:00Z")), null);
  assert.equal(boardOffset(train, new Date("2026-10-13T12:00:00Z")), 119);
  assert.equal(boardOffset(train, new Date("2026-10-13T19:00:00Z")), null);
});

const service = (extra = {}) => ({
  serviceID: "abc", std: "15:30", etd: "On time", platform: "5", operatorCode: "VT",
  subsequentCallingPoints: [{ callingPoint: [
    { crs: "WFJ", st: "15:50", et: "On time" },
    { crs: "EUS", st: "16:05", et: "On time" },
  ] }],
  ...extra,
});

test("a train is found by its id, or by its timetable when the id has changed", () => {
  const other = { serviceID: "zzz", std: "15:30", operatorCode: "LM", subsequentCallingPoints: [] };
  const board = { trainServices: [other, service()] };
  assert.equal(findService(board, train).serviceID, "abc");
  assert.equal(findService(board, { ...train, serviceID: "gone" }).serviceID, "abc");
  assert.equal(findService({ trainServices: [other] }, { ...train, serviceID: "gone" }), undefined);
});

test("state follows the board", () => {
  assert.deepEqual(stateFrom(service(), train, onTime), { ...onTime, platform: "5" });

  const late = stateFrom(service({ etd: "15:42", subsequentCallingPoints: [{ callingPoint: [
    { crs: "EUS", st: "16:05", et: "16:20" },
  ] }] }), train, onTime);
  assert.equal(late.expectedDeparture, "15:42");
  assert.equal(late.expectedArrival, "16:20");
  assert.equal(late.delayMinutes, 15);

  // Once the train has left, Darwin drops the platform and reports actual times
  const arrived = stateFrom(service({ platform: undefined, subsequentCallingPoints: [{ callingPoint: [
    { crs: "EUS", st: "16:05", at: "16:09" },
  ] }] }), train, { ...onTime, platform: "5" });
  assert.equal(arrived.platform, "5");
  assert.equal(arrived.hasArrived, true);
  assert.equal(arrived.delayMinutes, 4);

  assert.equal(stateFrom(service({ isCancelled: true }), train, onTime).isCancelled, true);
  assert.equal(stateFrom(service({ etd: "Delayed" }), train, onTime).hasUnknownDelay, true);
});

test("alerts match the app's wording", () => {
  const bodies = (old, next, extra = {}) => changes({ ...train, ...extra }, old, next, before).alerts.map((a) => a.body);

  assert.deepEqual(bodies(onTime, { ...onTime, platform: "5" }), ["Leaves from platform 5."]);
  assert.deepEqual(bodies({ ...onTime, platform: "5" }, { ...onTime, platform: "7" }), ["Platform changed to 7 (was 5)."]);
  assert.deepEqual(bodies(onTime, { ...onTime, expectedDeparture: "15:42", delayMinutes: 12 }),
    ["Running 12 min late. Now expected to leave at 15:42."]);
  assert.deepEqual(bodies(onTime, { ...onTime, expectedArrival: "16:17", delayMinutes: 12 }),
    ["Running 12 min late. Now expected to arrive at 16:17."]);
  assert.deepEqual(bodies(onTime, { ...onTime, isCancelled: true }), ["This train has been cancelled."]);
  assert.deepEqual(bodies({ ...onTime, isCancelled: true }, { ...onTime, isCancelled: true, platform: "9" }), []);
  assert.deepEqual(bodies(onTime, { ...onTime, hasUnknownDelay: true }), ["Delayed. No new time has been given yet."]);
  assert.deepEqual(bodies({ ...onTime, delayMinutes: 12 }, onTime, { alertedDelay: 12 }), ["Back on time."]);
  assert.deepEqual(bodies(onTime, { ...onTime, hasArrived: true, delayMinutes: 9 }), []);
});

test("a creeping delay is reported in steps", () => {
  const at = (delayMinutes) => ({ ...onTime, expectedDeparture: "15:45", delayMinutes });
  let alerted = 12;
  const step = (from, to) => {
    const result = changes({ ...train, alertedDelay: alerted }, at(from), at(to), before);
    alerted = result.alertedDelay;
    return result.alerts.length;
  };
  assert.equal(step(12, 14), 0);
  assert.equal(step(14, 16), 0);
  assert.equal(step(16, 17), 1);
  assert.equal(alerted, 17);
});

test("no platform alert once the train has left", () => {
  const after = new Date("2026-10-13T14:45:00Z");
  assert.deepEqual(changes(train, onTime, { ...onTime, platform: "5" }, after).alerts, []);
});

test("the Live Activity's content state", () => {
  assert.deepEqual(contentState(train, { ...onTime, platform: "5", delayMinutes: 3, expectedDeparture: "15:33" }), {
    scheduledDeparture: "15:30", expectedDeparture: "15:33", delayMinutes: 3, platform: "5", isCancelled: false,
  });
});
