import express from "express";

// You may use this value in your routes to determine the max number of boxes,
// so that you can return the next and previous box numbers in the response headers.

import { Box } from '../data/schema.js';
const router = express.Router();

// TODO Handler for GET /:boxNumber
// GET /api/boxes/:boxNumber
router.get('/:boxNumber', async (req, res) => {
  const num = parseInt(req.params.boxNumber, 10);
  if (isNaN(num) || num < 1) return res.status(400).json({ error: 'Invalid box number' });

  const totalBoxes = parseInt(process.env.NUM_BOXES, 10) || await Box.countDocuments();
  const box = await Box.findOne({ boxNumber: num }).populate({ path: 'pokemon', retainNullValues: true });
  if (!box) return res.status(404).json({ error: 'Box not found' });

  if (num > 1) res.set('previous-box', String(num - 1));
  if (num < totalBoxes) res.set('next-box', String(num + 1));

  res.json(box);
});
// TODO Handler for PATCH /
// PATCH /api/boxes
router.patch('/', async (req, res) => {
  const { swap } = req.body;
  if (!swap || !swap.source || !swap.target) return res.status(422).json({ error: 'Data format error' });

  const sNum = parseInt(swap.source.boxNumber, 10);
  const tNum = parseInt(swap.target.boxNumber, 10);
  const sSlot = parseInt(swap.source.slotNumber, 10) - 1;
  const tSlot = parseInt(swap.target.slotNumber, 10) - 1;
  if ([sNum, tNum, sSlot, tSlot].some(n => isNaN(n) || n < 0)) return res.status(422).json({ error: 'Data format error' });

  const [sourceBox, targetBox] = await Promise.all([
    Box.findOne({ boxNumber: sNum }),
    Box.findOne({ boxNumber: tNum }),
  ]);
  if (!sourceBox || !targetBox) return res.status(404).json({ error: 'Source or destination box not found' });

  const sourcePokemon = sourceBox.pokemon[sSlot];
  if (sourcePokemon == null) return res.status(404).json({ error: 'Source slot empty' });

  // Swap
  const targetPokemon = targetBox.pokemon[tSlot] || null;
  sourceBox.pokemon[sSlot] = targetPokemon;
  targetBox.pokemon[tSlot] = sourcePokemon;

  await Promise.all([sourceBox.save(), targetBox.save()]);
  res.status(204).end();
});

export default router;
