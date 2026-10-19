import { createRoot } from "react-dom/client";
import { flushSync } from "react-dom";
import { BriefInput } from "../src/BriefInput.tsx";
import { Review } from "../src/schema.ts";

const root = createRoot(document.getElementById("app")!);
let node = new Review({ reviewer: "Old", approved: false });
let value = "Old";
let disabled = false;
const render = () => flushSync(() => root.render(
  <BriefInput field="review.reviewer" node={node} value={value} disabled={disabled}
    onValue={next => { value = next; render(); }} onFocus={() => {}} onBlur={() => {}} />,
));
render();
Object.assign(window, { fixture: {
  replace() { node = new Review({ reviewer: "New", approved: false }); value = "New"; render(); },
  disconnect() { disabled = true; render(); },
  reconnect() { disabled = false; render(); },
  get reviewer() { return value; },
} });
