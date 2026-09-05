import React from "react";
import ReactDOM from "react-dom/client";
import { ApplicationInsights } from "@microsoft/applicationinsights-web";
import App from "./App";
import "./styles.css";

// Read connection string from window global (set by config.js at runtime)
const connectionString =
  (window as any).APPINSIGHTS_CONNECTION_STRING ||
  "InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://localhost;LiveEndpoint=https://localhost";

const appInsights = new ApplicationInsights({
  config: {
    connectionString,
    enableAutoRouteTracking: false, // Manual tracking in App.tsx
    enableCorsCorrelation: true,
    enableRequestHeaderTracking: true,
    enableResponseHeaderTracking: true,
  },
});

appInsights.loadAppInsights();
appInsights.trackPageView();

// Global error tracking
window.addEventListener("error", (event) => {
  appInsights.trackException({
    exception: event.error || new Error(event.message),
    severityLevel: 3,
  });
});

window.addEventListener("unhandledrejection", (event) => {
  appInsights.trackException({
    exception: new Error(`Unhandled promise rejection: ${event.reason}`),
    severityLevel: 3,
  });
});

// Expose appInsights for route tracking in App.tsx
(window as any).appInsights = appInsights;

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);