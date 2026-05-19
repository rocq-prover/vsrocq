import React from "react";
import { flushSync } from "react-dom";
import { createRoot } from "react-dom/client";
import App from "./App";

const container = document.getElementById("root")!;
const root = createRoot(container);

// we make sure that the first render is synchronous, allowing us to immediately
// send events to the webview without worrying about the component not being ready yet.
flushSync(() => {
  root.render(
    <React.StrictMode>
      <App />
    </React.StrictMode>,
  );
})
