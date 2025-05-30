import React from 'react';
import { Routes, Route, Navigate } from "react-router-dom";
import BoxPage from './components/BoxPage';
export default function App() {
  return (
      <Routes>
        <Route path="/" element={<Navigate replace to="/boxes/1" />} />
        <Route path="/boxes/:boxNumber" element={<BoxPage />} />
        <Route path="*" element={<Navigate to="/boxes/1" replace />} />
      </Routes>
  );
}

