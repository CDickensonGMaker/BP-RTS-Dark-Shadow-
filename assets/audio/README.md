# Audio Assets - Dark Shadows RTS

Drop your audio files in the appropriate folders. Supported formats: .ogg, .mp3, .wav

## Folder Structure

```
audio/
├── music/           # Background music tracks
├── sfx/
│   ├── combat/      # Weapon sounds, impacts, deaths
│   ├── ui/          # UI clicks, alerts
│   └── ambient/     # Environmental loops
└── voice/
    ├── orders/      # Order acknowledgments ("Yes, my lord!")
    ├── combat/      # Battle cries, grunts
    └── morale/      # Routing cues, victory/defeat stings
```

## File Naming Conventions

### Music (music/)
- `music_calm.ogg` - Peaceful deployment/pre-battle
- `music_battle_light.ogg` - Light combat
- `music_battle_intense.ogg` - Intense battle
- `music_victory.ogg` - Victory sting
- `music_defeat.ogg` - Defeat sting

### Order Acknowledgments (voice/orders/)
Each order type needs 5+ variants to avoid repetition:
- `order_select_01.ogg` through `order_select_05.ogg`
- `order_move_01.ogg` through `order_move_05.ogg`
- `order_attack_01.ogg` through `order_attack_05.ogg`
- `order_charge_01.ogg` through `order_charge_05.ogg`
- `order_retreat_01.ogg` through `order_retreat_05.ogg`
- `order_formation_01.ogg` through `order_formation_05.ogg`
- `order_guard_01.ogg` through `order_guard_05.ogg`

Lines should be:
- Short (<1.5s)
- Faction-specific accent/language
- Multiple variants per command

### Combat SFX (sfx/combat/)
- `sword_hit_01.ogg` through `sword_hit_05.ogg`
- `sword_miss_01.ogg`
- `arrow_fire_01.ogg`
- `arrow_hit_01.ogg` through `arrow_hit_03.ogg`
- `shield_block_01.ogg` through `shield_block_03.ogg`
- `death_01.ogg` through `death_05.ogg`
- `cavalry_charge_01.ogg`
- `hooves_01.ogg`
- `war_cry_01.ogg`
- `volley_fire_01.ogg`

### Morale Events (voice/morale/)
Critical audio cues per §16.2:
- `unit_routing.ogg` - Horror cue when unit breaks
- `cavalry_charge_incoming.ogg` - Drum hit / horn warning
- `ammo_empty.ogg` - Quiet click when out of ammo
- `battle_won.ogg` - Victory sting
- `battle_lost.ogg` - Defeat sting

### Ambient (sfx/ambient/)
- `ambient_wind_01.ogg`
- `ambient_birds_01.ogg`
- `ambient_battlefield_01.ogg` - Distant fighting loop

## Audio Bus Setup

In Godot: Project Settings > Audio > Buses, create:
- Master
  - Music (for background tracks)
  - Ambient (for environmental loops)
  - Voice (for order acknowledgments)
  - SFX (for combat sounds)
  - UI (for interface clicks)

## Tips

1. Use .ogg for music and ambient (good compression, looping)
2. Use .wav for short SFX (no compression delay)
3. Keep voice lines SHORT - under 1.5 seconds
4. Provide 5+ variants for frequently played sounds
5. Normalize audio levels before importing
