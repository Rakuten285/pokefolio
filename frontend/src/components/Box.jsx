import React from 'react';
import Slot from './Slot';
import './Box.css';
export default function Box({ box, swap }) {
  return (
    <div className="box-grid">
      {box.pokemon.map((pokemon, idx) => (
        <Slot key={idx} pokemon={pokemon} slotIndex={idx} boxNumber={box.boxNumber} swap={swap} />
      ))}
    </div>
  );
}
