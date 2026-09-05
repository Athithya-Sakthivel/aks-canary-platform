import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter } from "react-router";
import { ApplicationInsights } from "@microsoft/applicationinsights-web";
import App from "./App";
import "./styles.css";
import "./types";

function createApplicationInsights(): ApplicationInsights | undefined {
  const connectionString = window.APPINSIGHTS_CONNECTION_STRING?.trim();

  if (!connectionString) {
    console.warn(
      "Application Insights is disabled: APPINSIGHTS_CONNECTION_STRING is not configured.",
    );
    return undefined;
  }

  if (!/^InstrumentationKey=[^;]+(?:;.*)?$/i.test(connectionString)) {
    console.error(
      "Application Insights is disabled: APPINSIGHTS_CONNECTION_STRING does not look like a valid Azure Application Insights connection string.",
    );
    return undefined;
  }

  const appInsights = new ApplicationInsights({
    config: {
      connectionString,
      enableAutoRouteTracking: true,
      enableCorsCorrelation: true,

      // Do not collect HTTP headers by default. In particular, keep
      // authentication-related headers out of telemetry.
      enableRequestHeaderTracking: false,
      enableResponseHeaderTracking: false,
    },
  });

  appInsights.loadAppInsights();
  appInsights.trackPageView();

  return appInsights;
}

const appInsights = createApplicationInsights();

window.appInsights = appInsights;

const rootElement = document.getElementById("root");

if (!rootElement) {
  throw new Error('Required root element "#root" was not found.');
}

ReactDOM.createRoot(rootElement).render(
  <React.StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </React.StrictMode>,
);
