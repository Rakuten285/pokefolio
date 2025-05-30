import React from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import useBox from '../hooks/useBox';
import Box from './Box';
import './BoxPage.css';

export default function BoxPage() {
  // TODO Implement the BoxPage component as per the README instructions
  const { boxNumber } = useParams();
  const current = Number(boxNumber);
  const navigate = useNavigate();
  const { box, hasNext, hasPrevious, isPending, error, swap } = useBox(Number(boxNumber));

  return (
    <div className="box-container">
      <div className="box-header">
        <button
          className="nav-button"
          disabled={!hasPrevious}
          onClick={() => navigate(`/boxes/${current - 1}`)}
        >
          ←
        </button>

        <h1 className="title">Box #{current}</h1>

        <button
          className="nav-button"
          disabled={!hasNext}
          onClick={() => navigate(`/boxes/${current + 1}`)}
        >
          →
        </button>
      </div>

      {isPending && <p>Loading…</p>}
      {error && <p className="error">{error.message}</p>}
      {box && <Box box={box} swap={swap} />}
    </div>
  );
}
