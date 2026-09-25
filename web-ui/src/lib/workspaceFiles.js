const filenamePattern = /^[A-Za-z_][A-Za-z0-9_.-]*\.(?:v|vh|mem)$/;
const protectedFiles = new Set(['top.v', 'pinout.lpf']);

export function addWorkspaceFiles(current, entries) {
  const next = { ...current };
  const added = [];
  const errors = [];
  for (const [name, content] of entries) {
    if (!filenamePattern.test(name)) {
      errors.push(`${name}: use a flat .v, .vh, or .mem filename.`);
    } else if (Object.hasOwn(next, name)) {
      errors.push(`${name}: already exists; existing file was kept.`);
    } else {
      next[name] = content;
      added.push(name);
    }
  }
  return { files: next, added, errors };
}

export function removeWorkspaceFile(current, name) {
  if (protectedFiles.has(name)) return { files: current, error: `${name} cannot be removed.` };
  if (!Object.hasOwn(current, name)) return { files: current, error: `${name} does not exist.` };
  const next = { ...current };
  delete next[name];
  return { files: next, error: null };
}
