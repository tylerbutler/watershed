import assert from "node:assert/strict";
import test from "node:test";
import { requiredCheckIds, validateContract } from "../lib/contract.mjs";

function contract() {
  return {
    version: 1,
    task: "incident-response-board",
    groups: [
      { id: "local", description: "Local mutations" },
      { id: "collaboration", description: "Remote observation" },
    ],
    checks: [
      { id: "local.assignee-remove", group: "local", requirement: "Remove the optional assignee." },
      { id: "collaboration.remote", group: "collaboration", requirement: "Observe remote changes." },
    ],
  };
}

test("returns check IDs in declared order without changing the contract", () => {
  const value = contract();
  const original = structuredClone(value);
  assert.deepEqual(requiredCheckIds(value), ["local.assignee-remove", "collaboration.remote"]);
  assert.deepEqual(value, original);
});

test("rejects duplicate check identities before they can conceal a missing check", () => {
  const value = contract();
  value.checks[1].id = value.checks[0].id;
  assert.throws(() => validateContract(value), /duplicate check/i);
});

test("rejects checks assigned to an unknown group", () => {
  const value = contract();
  value.checks[0].group = "unknown";
  assert.throws(() => validateContract(value), /unknown group/i);
});

test("rejects a group with no executable checks", () => {
  const value = contract();
  value.checks.pop();
  assert.throws(() => validateContract(value), /no checks/i);
});

test("rejects malformed contracts instead of accepting partial defaults", () => {
  for (const value of [
    null,
    { ...contract(), version: 2 },
    { ...contract(), groups: [] },
    { ...contract(), checks: [] },
    { ...contract(), task: " " },
    { ...contract(), check: [] },
    { ...contract(), groups: [{ id: "local", description: "" }] },
    { ...contract(), groups: [...contract().groups, contract().groups[0]] },
    { ...contract(), checks: [{ ...contract().checks[0], requirement: "" }] },
  ]) {
    assert.throws(() => validateContract(value), TypeError);
  }
});
