# Career Thief BlackMarket

This mod changes Career Mode gameplay with a BlackMarket vehicle theft loop:

- steal a vehicle by aiming at it (key `K`)
- deliver the stolen vehicle to a `BlackMarket` dropoff (docks by default)
- create a local marketplace listing
- receive buyer offers and sell the vehicle

## Gameplay Loop

1. Look at a target vehicle and press `K` to attempt theft
2. Police is alerted immediately when theft starts
3. Drive the stolen vehicle to the dropoff area (docks)
4. If speed and integrity checks pass, a listing is created
5. Wait for offers, then accept/reject from the BlackMarket panel
6. Completed sale credits money to the player

## Anti-Exploit Rules

- You cannot steal your own player vehicle
- Cooldown applies after each theft attempt
- Mission fails if the stolen vehicle is lost/too far away
- Dropoff is rejected if:
  - speed is above the allowed limit
  - integrity is below the minimum threshold

## Configuration

`careerThief_config.json` controls balancing and behavior:

- `targeting`: target distance and aim cone
- `theft`: cooldown, wanted duration, max tracking distance
- `dropoff`: dropoff points (docks), radius, max speed, min integrity
- `marketplace`: price ranges and offer timing
- `progression`: levels 0->10, XP thresholds, cumulative bonuses
- `debug.debugMode`: enables `[CareerThief][INFO]` logs

## BlackMarket Level System

- Starting level: `0`
- Max level: `10`
- Progression: increasing XP thresholds
- Bonus model: cumulative bonuses

Main effects:

- Final sale price bonus
- Theft success chance bonus
- Instant theft chance bonus
- Chance to avoid police call on failed theft (up to `+25%` at level 10)

## Police Integration

The module uses native BeamNG APIs:

- `gameplay_police`
- `gameplay_traffic`

With legacy fallback to `career_modules_lawEnforcement` when needed.

## Important Files

- `lua/ge/extensions/career/modules/thief.lua`: theft logic + mission flow + marketplace
- `careerThief_config.json`: balancing and dropoff configuration
- `ui/modules/apps/careerThief/app.js`: UI controller
- `ui/modules/apps/careerThief/app.html`: HUD + BlackMarket panel
- `ui/modules/apps/careerThief/app.css`: HUD styling
