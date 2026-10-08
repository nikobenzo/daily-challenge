# Water

## Agreed behavior

- Daily target: 4,000 ml, not a US or imperial gallon.
- Main + control adds one 450 ml pour to today.
- Main − control undoes the latest active pour in the selected day; the main popup defaults to today.
- Disable minus when no active pour remains. Never create a negative total.
- Provide a secondary custom-amount action using positive whole millilitres.
- Sum active pours to derive the true total. Nine standard pours equal 4,050 ml and satisfy the target.
- Retain amounts above the target; never clamp stored totals to 4,000 ml.
- Correcting water below 4,000 ml makes the requirement incomplete and recalculates day completion and streaks.

## Visual behavior

The jug represents exactly 4 litres. Fill height reaches its maximum at 4,000 ml; additional water produces brief procedural overflow, droplets, and spills. The recorded total remains available as small text and an accessible value. No implication that the jug itself holds more than 4 litres.

Overflow is animated feedback, not a prompt to keep drinking beyond the goal. Hide or stop animation when the popup is closed; use static feedback with Reduce Motion.

## Data and sync proposal

Each pour has a unique identity, positive amount, challenge date, and ordering metadata. Undo targets a specific pour and retains an audit record rather than erasing its existence. Replaying a sync operation must not duplicate a pour or apply the same undo twice. Distinct offline additions on both Macs must both survive.

Corrections use the explicitly selected date, not the date when the edit is made. Concurrent ordering and undo behavior must be deterministic and tested before release; unseen remote pours must not be implicitly undone.

## Acceptance tests

- Eight standard pours: 3,600 ml, incomplete.
- Nine: 4,050 ml, complete, brief overflow.
- Undo ninth: 3,600 ml, incomplete again.
- Empty undo: no change.
- Mixed custom and standard amounts calculate exactly using integer millilitres.
- Both Macs add offline: both entries appear once after sync.
- Both Macs undo the same known pour: it is removed from the active total once.
- Yesterday's correction never changes today's water total.
