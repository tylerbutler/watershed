function record(value, keys, label) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError(`${label} must be an object`);
  }
  const unknown = Object.keys(value).filter(key => !keys.includes(key));
  if (unknown.length) throw new TypeError(`${label} has unknown fields: ${unknown.join(", ")}`);
}

function text(value, label) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new TypeError(`${label} must be a nonempty string`);
  }
}

export function validateContract(value) {
  record(value, ["version", "task", "groups", "checks"], "Contract");
  if (value.version !== 1) throw new TypeError("Unsupported contract version");
  text(value.task, "Contract task");
  if (!Array.isArray(value.groups) || value.groups.length === 0) {
    throw new TypeError("Contract must declare at least one group");
  }
  if (!Array.isArray(value.checks) || value.checks.length === 0) {
    throw new TypeError("Contract must declare at least one check");
  }
  const groups = new Map();
  for (const group of value.groups) {
    record(group, ["id", "description"], "Group");
    text(group.id, "Group ID");
    text(group.description, "Group description");
    if (groups.has(group.id)) throw new TypeError(`Duplicate group: ${group.id}`);
    groups.set(group.id, 0);
  }
  const ids = new Set();
  for (const check of value.checks) {
    record(check, ["id", "group", "requirement"], "Check");
    text(check.id, "Check ID");
    text(check.requirement, "Check requirement");
    if (ids.has(check.id)) throw new TypeError(`Duplicate check: ${check.id}`);
    if (!groups.has(check.group)) throw new TypeError(`Unknown group for check ${check.id}`);
    ids.add(check.id);
    groups.set(check.group, groups.get(check.group) + 1);
  }
  for (const [id, count] of groups) {
    if (count === 0) throw new TypeError(`Group ${id} has no checks`);
  }
  return value;
}

export function requiredCheckIds(contract) {
  return validateContract(contract).checks.map(check => check.id);
}
