import { Navigate, Route, Routes } from "react-router";
import ProtectedRoute from "./components/ProtectedRoute";
import Login from "./pages/Login";
import Register from "./pages/Register";
import Tasks from "./pages/Tasks";

export default function App() {
  const showCanaryBadge = import.meta.env.VITE_CANARY_BADGE === "true";

  return (
    <>
      {showCanaryBadge && (
        <div
          aria-label="Canary version"
          style={{
            position: "fixed",
            top: "10px",
            right: "10px",
            background: "red",
            color: "white",
            padding: "5px 10px",
            borderRadius: "4px",
            zIndex: 9999,
          }}
        >
          v2
        </div>
      )}

      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/register" element={<Register />} />

        <Route
          path="/tasks"
          element={
            <ProtectedRoute>
              <Tasks />
            </ProtectedRoute>
          }
        />

        <Route path="/" element={<Navigate to="/tasks" replace />} />
        <Route path="*" element={<Navigate to="/login" replace />} />
      </Routes>
    </>
  );
}
