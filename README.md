<div align="center">

# <img src="Docs/img/logo.png" alt="" width="48" align="absmiddle">&nbsp;&nbsp;&nbsp;XP Horizon&nbsp;&nbsp;&nbsp;<img src="Docs/img/logo.png" alt="" width="48" align="absmiddle">

**Hold Shift over the XP bar to see your total progress to level 60, and when you will get there.**

[![Latest release](https://img.shields.io/github/v/release/thejvfdev/xp-horizon)](https://github.com/thejvfdev/xp-horizon/releases/latest)
[![License](https://img.shields.io/github/license/thejvfdev/xp-horizon)](LICENSE)
![Game](https://img.shields.io/badge/game-WoW%20Forever-blue)

[**Download the latest release**](https://github.com/thejvfdev/xp-horizon/releases/latest)

<br>

<img src="Docs/img/tooltip.png" alt="The XP Horizon tooltip, showing the percentage to level 60 and the time estimate">

</div>

## What it does

The XP bar shows progress through your current level. XP Horizon shows progress through the whole climb to level 60, counting all the XP from level 1.

1. Hover your XP bar and hold **Shift**.
2. The bar fills in green to show your total progress, with the percentage and your XP out of the total on it.
3. The tooltip lists your level, XP earned and remaining, rested XP, and an estimate of when you will reach 60.
4. Let go of Shift and the normal bar and tooltip come back.

<img src="Docs/img/xp-bar.png" alt="The XP bar filled in green to show progress to level 60" width="100%">

### The estimate

The tooltip works out your average XP per hour from your total XP and your /played time, then applies it to the XP you still need. It shows your time played, XP per hour played, the time left to 60, and your total /played at level 60.

## Installation

1. Download the latest release and extract the `XpHorizon` folder.
2. Put it in `World of Warcraft\_forever_\Interface\AddOns\`.
3. Restart the game or type `/reload`.

## How the numbers are worked out

- **XP per level.** The addon starts with the original Classic XP table, 4,084,700 XP from level 1 to 60. The game only reports the XP needed for the level a character is currently at, so each time a character is seen at a level, the addon saves that value in `XpHorizonDb` and uses it from then on. If Forever's table differs from Classic's, the totals correct themselves for every level you have played.
- **Time estimate.** Your total XP divided by your total /played gives an average XP per second. The XP still needed is divided by that rate. XP per hour usually rises as you level, so the estimate tends to run long.
- **/played.** The game only lets addons read /played by asking the server, and the reply is always printed in chat. The addon asks once per session, the first time you open the Shift view. Typing `/played` yourself updates the estimate too.

## Limitations

- The level cap is fixed at 60.
- The text is English only.

## License

[GPL-3.0-or-later](LICENSE)
