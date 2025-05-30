import React from 'react';
import './Slot.css';
export default function Slot({ pokemon, boxNumber, slotIndex, swap }) {
  const slotNum = slotIndex + 1;
  const handleDrop = (e) => {
    const data = JSON.parse(e.dataTransfer.getData('application/json'));
    swap(data, { boxNumber, slotNumber: slotNum });
  };

  return (
    <div
      className="slot"
      draggable={!!pokemon}
      onDragStart={() =>
        pokemon &&
        window.event.dataTransfer.setData(
          'application/json',
          JSON.stringify({ boxNumber, slotNumber: slotNum })
        )
      }
      onDragOver={(e) => e.preventDefault()}
      onDrop={handleDrop}
    >
      {pokemon ? (
        <>
          <img src={pokemon.isShiny ? pokemon.shinyImageUrl : pokemon.normalImageUrl} alt={pokemon.name} />
          <p>{pokemon.name} {pokemon.isShiny && '✨'}</p>
        </>
      ) : (
        <div className="overlay">Empty</div>
      )}
    </div>
  );
}
