# Replace Warehouses

In Transport Fever 3 you cannot place a specialised warehouse on top of an existing one, the game reports a collision. Demolishing the old warehouse first throws away everything stored in it. Replace Warehouses lets you change the type of a warehouse module right where it stands and keeps the cargo.

## Features

- New card "Rebuild warehouse" in the warehouse window: pick a new type per module (universal, goods, bulk, liquid, flatbed) and click "Rebuild"
- The module is swapped in its slot: no collision, position and connections stay the same, cargo that fits the new module stays in the warehouse
- Cargo that no longer fits: the game pauses and a window lists the modules you need, for example "1x Goods module: Bricks 200"
- Discard the cargo, or build a suitable warehouse or module: the build menu opens, a small info window stays visible and the cargo is stored automatically after building, then the game continues
- Also catches cargo lost when a module is removed or a whole warehouse is demolished the normal way
- Waiting cargo is saved with the savegame
- German, English and French

## Good to know

Cargo can only be put back into specialised modules, a universal module cannot take back a specific cargo type. The mod sets the receiving module to that cargo type, you can reset it in the warehouse window at any time.

## Installation

Copy the folder `nalathan_lager_ersetzen` into your Transport Fever 3 local mods folder and activate "Replace Warehouses" when loading a savegame.

## Feedback

Bug reports and feature requests are welcome through GitHub Issues. Please include mod version, game version and a short description of what happened. `stdout.txt` from the `crash_dump` folder helps if the game shows a Lua error.

## Links

- Website: https://www.nalathan.de/
- YouTube: https://www.youtube.com/@nalathangaming
- Issues: https://github.com/Nalathan01/TF3_ReplaceWarehouses/issues
