# Audio Assets Setup

This document explains the audio files needed for Restaurant Flows and where to place them.

## Directory Structure

```
assets/
└── audio/
	└── sfx/  (Sound Effects)
```

## Required Sound Effect Files

All sound files should be placed in `assets/audio/sfx/` directory.
Supported formats: `.wav`, `.ogg`, or `.mp3`

### Order Sounds
- **`order_ding.wav`** - Bell/ding sound when customer places an order
  - Suggested: Pleasant notification sound, 0.5-1 second duration
  - Example: Cash register ding, service bell, or chime

### Customer Satisfaction Sounds
- **`customer_happy.wav`** - Sound when customer is very satisfied (>70%)
  - Suggested: Cheerful sound, laugh, or positive acknowledgment
  - Example: "Yay!", upbeat chime, or happy voice

- **`customer_neutral.wav`** - Sound when customer satisfaction is medium (30-60%)
  - Suggested: Neutral "hmm" or waiting sound
  - Example: Sigh, neutral hum, or gentle tap

- **`customer_angry.wav`** - Sound when customer is unhappy (<30%)
  - Suggested: Angry sound, complaint, or frustrated noise
  - Example: Grumble, complaint sound, or negative buzzer

### Cooking Sounds (Looping)
These sounds should loop smoothly for continuous cooking:

- **`cooking_oven.wav`** - Oven cooking sound (for pizza)
  - Suggested: Low rumble, gentle heat sound
  - Must loop: Yes (set to loop in Godot)
  - Duration: 2-5 seconds loopable

- **`cooking_sizzle.wav`** - Sizzling sound for stove (burger, pasta, soup)
  - Suggested: Sizzling, frying sound
  - Must loop: Yes
  - Duration: 2-5 seconds loopable

- **`cooking_chop.wav`** - Chopping/preparation sound (salad)
  - Suggested: Knife chopping on cutting board
  - Must loop: Yes
  - Duration: 1-3 seconds loopable

- **`cooking_generic.wav`** - Fallback generic cooking sound
  - Suggested: Any cooking ambience
  - Must loop: Yes
  - Duration: 2-5 seconds loopable

## Audio Settings

The game includes an AudioManager singleton with the following settings:
- **Master Volume**: 100% (adjustable)
- **Music Volume**: 70% (adjustable)
- **SFX Volume**: 80% (adjustable)

All 3D positioned sounds (customer sounds, cooking sounds) use:
- **Attenuation**: Inverse distance
- **Max Distance**: 12-20 units (varies by sound type)

## Creating/Finding Audio

### Free Audio Resources
1. **Freesound.org** - https://freesound.org/
2. **OpenGameArt.org** - https://opengameart.org/
3. **Zapsplat.com** - https://www.zapsplat.com/
4. **BBC Sound Effects** - https://sound-effects.bbcrewind.co.uk/

### AI Audio Generation
- **ElevenLabs** (voice and sound effects)
- **Soundraw** (music and ambience)
- **Riffusion** (music generation)

### Making Your Own
- **Audacity** (free audio editor) - https://www.audacityteam.org/
- **LMMS** (free music creation) - https://lmms.io/
- Record sounds with your phone and edit in Audacity

## Loop Setup in Godot

For looping cooking sounds:
1. Import the audio file into Godot
2. Select the file in the FileSystem
3. In the Import panel, set:
   - **Loop**: ON
   - **Loop Offset**: 0

## Testing

After adding audio files:
1. Run the game with `mcp__godot__run_project`
2. Press **F7** to spawn customers
3. Press **F6** to spawn waiters
4. Listen for:
   - Order ding when waiter takes order
   - Cooking sounds when food is on stations
   - Customer satisfaction sounds when happiness changes
5. Check debug output for missing audio warnings

## Current Implementation

All audio hooks are already implemented in the game code:
- ✅ AudioManager singleton created
- ✅ Order sounds on order placement
- ✅ Customer satisfaction sounds
- ✅ Cooking station looping sounds
- ✅ 3D spatial audio positioning
- ⚠️ Audio files need to be added to `assets/audio/sfx/`

## Particle Effects (No Audio Files Needed)

The following visual effects are already implemented:
- ✅ Steam particles on cooking stations (no audio needed)
- ✅ Satisfaction stars for happy customers (no audio needed)

## Troubleshooting

If sounds don't play:
1. Check console for warnings like: `[AUDIO_MANAGER] Sound file not found: order_ding`
2. Verify files are in correct directory: `res://assets/audio/sfx/`
3. Check file extensions (`.wav`, `.ogg`, or `.mp3`)
4. Ensure files are imported in Godot's FileSystem panel

## Future Enhancements

Potential additions:
- Background music for restaurant ambience
- Door open/close sounds
- Footstep sounds for characters
- Food serving "clink" sound
- Level complete jingle
- Game over sound
