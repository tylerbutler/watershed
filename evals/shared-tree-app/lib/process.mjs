// Vally 0.19.0 does not export this owned-process utility on its public surface.
const { execFileTree } = await import(new URL("./utils/exec-tree.js", import.meta.resolve("@microsoft/vally")));
export async function execOwned(command, args, options) {
  try { return await execFileTree(command, args, options); }
  catch (error) {
    if (error.stderr) error.message += `\n${error.stderr.slice(-6000)}`;
    if (error.incompleteCleanup) error.message += "\nOwned process-tree cleanup could not be confirmed";
    throw error;
  }
}
