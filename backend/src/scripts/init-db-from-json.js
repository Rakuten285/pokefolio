import "dotenv/config";
import mongoose from "mongoose";
import { Box, Pokemon } from "../data/schema.js";

// Read values from environment variables
const numBoxes = parseInt(process.env.NUM_BOXES) || 5;
const numSlots = parseInt(process.env.NUM_SLOTS) || 30;
const numSpecies = parseInt(process.env.NUM_SPECIES) || 898;

await mongoose.connect(process.env.DB_URL);
console.log("Connected to the database.");

// Clear data
await Pokemon.deleteMany({});
await Box.deleteMany({});
console.log("Cleared existing data.");

import pokemonData from "./cs732-test-2025.pokemons.json" assert { type: "json" };
import boxData from "./cs732-test-2025.boxes.json" assert { type: "json" };

const dbPokemon = pokemonData.map((p) => new Pokemon({ ...p, _id: p._id.$oid }));
await Pokemon.insertMany(dbPokemon);

const dbBoxes = boxData.map(
  (b) => new Box({ ...b, _id: b._id.$oid, pokemon: b.pokemon.map((p) => (p ? p.$oid : null)) })
);
await Box.insertMany(dbBoxes);
console.log("Inserted Pokémon and boxes from JSON files.");

await mongoose.disconnect();
console.log("Disconnected from the database.");
