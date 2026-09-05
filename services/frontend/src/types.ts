import type { ApplicationInsights } from "@microsoft/applicationinsights-web";

// ---------------------------------------------------------------------------
// Original domain types
// ---------------------------------------------------------------------------

export type TaskStatus = "PENDING" | "IN_PROGRESS" | "COMPLETED" | "CANCELLED";

export interface JwtResponse {
  token: string;
  type?: string;
  username?: string;
  role?: string;
}

export interface Task {
  id: number;
  title: string;
  description: string | null;
  status: TaskStatus;
  userId: number;
  createdAt: string;
  updatedAt: string;
}

export interface TaskRequest {
  title: string;
  description?: string | null;
  status?: TaskStatus;
}

export interface TaskResponse {
  id: number;
  title: string;
  description: string | null;
  status: TaskStatus;
  userId: number;
  createdAt: string;
  updatedAt: string;
}

export interface LoginRequest {
  username: string;
  password: string;
}

export interface RegisterRequest {
  username: string;
  email: string;
  password: string;
}

// ---------------------------------------------------------------------------
// Runtime globals
// ---------------------------------------------------------------------------

declare global {
  interface Window {
    APPINSIGHTS_CONNECTION_STRING?: string;
    appInsights?: ApplicationInsights;
  }
}
