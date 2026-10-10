// Caret movement keys differ by platform; the shortcut modifier itself is
// Playwright's ControlOrMeta.
const mac = process.platform === "darwin";

export const lineEnd = mac ? "Meta+ArrowRight" : "End";
export const documentStart = mac ? "Meta+ArrowUp" : "Control+Home";
export const documentEnd = mac ? "Meta+ArrowDown" : "Control+End";
