import mongoose from "mongoose";
const Schema = mongoose.Schema;

// TODO Your schemas and mongoose.models here
const pokemonSchema = new Schema({
  dexNum: Number,
  name: { type: String, required: true },
  isShiny: Boolean,
  normalImageUrl: String,
  shinyImageUrl: String,
});

const boxSchema = new Schema({
  boxNumber: { type: Number, required: true, unique: true },
  pokemon: [{ type: Schema.Types.ObjectId, ref: 'Pokemon' }],
});

export const Pokemon = mongoose.model('Pokemon', pokemonSchema);
export const Box = mongoose.model('Box', boxSchema);