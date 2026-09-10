# Egg Pet MVP Design

Date: 2026-09-07

## Summary

This MVP is a gentle 2D hand-drawn mobile landscape game centered on hatching and raising a strange but soft pet. The player cares for one common egg on a floating island, helps it hatch into the first pet, Shell Pudding, and continues building intimacy through small scene-based interactions.

The care loop is the main game. Minigames are optional entertainment and do not produce resources, progression, memory entries, or core stat changes in the MVP.

## Goals

- Build a complete egg-to-pet care loop.
- Make the main island feel clean, warm, and interactive without permanent care buttons.
- Use visible pet and scene feedback instead of management-heavy UI.
- Support a future multi-egg, multi-species structure while implementing only one egg and one pet.
- Include one lightweight survivor-style minigame as an optional activity.
- Keep all negative states mild and recoverable.

## Non-Goals

- No shop, coins, materials, or item economy.
- No actual multi-species content beyond data structure preparation.
- No complex roguelike build system.
- No death, abandonment, permanent failure, or harsh punishment.
- No minigame rewards beyond win or loss result animation.

## Platform And Presentation

The final target is mobile landscape. PC is used for development and debugging, with mouse and keyboard allowed as temporary input substitutes.

The visual style is 2D hand-drawn cute, with a clean floating island as the main care space. The main screen should prioritize the egg, Shell Pudding, and interactable island objects over visible interface controls.

## Core Experience

The player starts with one common egg on a small floating island. The egg changes over real time and through active care. The player reads its needs through motion, expression, and scene state, then interacts with island objects to care for it.

When the egg reaches the hatch-ready state, the game plays a short hatching presentation and reveals Shell Pudding. Shell Pudding continues living on the same island and responds to food, warmth, cleaning, toys, and companionship.

## First Pet Concept

Shell Pudding is a soft, strange, affectionate creature. It has a pudding-like body and a cracked eggshell cap. It moves by squishing and bouncing. When happy, it wiggles or spins under its shell; when unsure, it hides beneath the shell and peeks out.

The MVP should use mixed animation:

- Programmatic animation for idle breathing, wobbling, bouncing, hiding, quick reactions, victory, and loss.
- Frame animation support reserved for later high-value moments such as hatching, petting, sleeping, and special intimacy actions.

Game logic calls creature actions by action name, so later sequence-frame assets can replace or augment procedural animations without rewriting care logic.

## Care Model

The MVP tracks four core states, each in the range `0-100`:

- Temperature
- Hunger
- Cleanliness
- Mood

The comfortable range is approximately `60-100`. Below `40`, the creature or egg should visibly express a need. Below `20`, it should show a mild negative behavior such as hiding, moving slowly, looking messy, or becoming less responsive.

There is no death, permanent failure, or irreversible damage. Low states are meant to invite care, not punish the player.

## Scene-Based Interaction

The main island does not use a permanent right-side or bottom care toolbar. Care happens through scene objects and creature feedback.

Required MVP interactables:

- Egg nest or pet resting area.
- Food bowl, used to place food. After food is placed, Shell Pudding may autonomously approach and eat.
- Warm lamp or equivalent heating object, used to adjust warmth.
- Cleaning object, such as a small water bowl or cloth.
- Toy or companionship object.
- Minigame Hub entrance, visible on the main island or as a light UI element.

Temporary UI may appear after interacting with an object, such as choosing food for the bowl or choosing a minigame. Default screen state should remain visually clean.

## Offline Progress

The game stores the last save time. On load, it computes elapsed time and applies gentle offline progress:

- Hatch progress increases slowly.
- Hunger, cleanliness, and mood decay lightly with safety floors.
- Temperature drifts according to environment and heating state.
- Long absences may trigger a mild event presentation, such as a messy island or Shell Pudding hiding under its shell.

Offline decay must have safe lower bounds and must not create severe punishment.

## Growth And Intimacy

Egg growth tracks hatch progress from `0-100`. Reaching `100` puts the egg into a hatch-ready state. Hatching should be player-triggered or clearly presented, not an abrupt automatic swap.

After hatching, intimacy begins. The MVP has three intimacy levels:

- Stranger
- Comfortable
- Close

Care and comfortable conditions increase intimacy slowly. The first version prioritizes action feedback. Each intimacy level should unlock or improve a small action, such as approaching the player, happy wobbling, or relaxed petting response.

Text and autonomous behavior can exist lightly, but the MVP priority is visible animation feedback.

## Minigame Structure

The project should support more than one minigame later, but the MVP implements only Bubble Survivor.

The minigame structure is:

- Minigame Hub: opened from a visible main island entrance.
- Bubble Survivor: the first available minigame.
- Future minigames: added later through the same hub.

The main care system should not know internal minigame rules.

## Bubble Survivor MVP

Bubble Survivor is a lightweight survivor-style minigame:

- Player controls Shell Pudding movement only.
- Shell Pudding automatically fires bubble bullets at the nearest enemy.
- Enemies approach the player.
- The session lasts a short fixed duration or ends on simple win/loss conditions.
- On completion, the game returns to the island and plays either a victory or loss animation.

Bubble Survivor does not give coins, materials, intimacy, mood, memory, hatch progress, or any other care reward in the MVP.

## Save Data

The main save data should include:

- Current stage: `egg` or `pet`.
- Egg type: `common_egg`.
- Pet species after hatching: `shell_pudding`.
- Core state values.
- Hatch progress and hatch-ready flag.
- Intimacy points and intimacy level.
- Unlocked action names.
- Scene object state, such as food bowl contents and warm lamp state.
- Last saved timestamp.

Memory records may be structurally supported, but minigames should not write memories in the MVP.

## Suggested Godot Scene Structure

- `main_island.tscn`: floating island care scene and main flow.
- `egg_view.tscn`: egg presentation and egg-stage action playback.
- `pet_view.tscn`: Shell Pudding presentation and pet-stage action playback.
- `interactable_item.tscn`: reusable interactable object base.
- `food_bowl.tscn`: food placement interaction.
- `warm_lamp.tscn`: warmth interaction.
- `clean_tool.tscn`: cleaning interaction.
- `toy.tscn`: companionship interaction.
- `minigame_hub.tscn`: minigame selection UI.
- `bubble_survivor.tscn`: first minigame.

## Suggested Script Structure

- `care_state.gd`: state ranges, deltas, comfort checks, and clamping.
- `growth_state.gd`: hatch progress, hatch-ready state, intimacy, and action unlocks.
- `save_data.gd`: save data resource or serializable data structure.
- `save_service.gd`: save, load, and offline progress application.
- `creature_animator.gd`: action-name playback for procedural and future frame animations.
- `interactable_item.gd`: shared interaction behavior.
- `minigame_hub.gd`: minigame selection and scene transition.
- `bubble_survivor_controller.gd`: Bubble Survivor rules.

## Implementation Phases

### Phase 1: Main Island Prototype

Create the mobile landscape floating island prototype with placeholder art. Include the egg nest, food bowl, warm lamp, cleaning object, toy or companionship object, and a visible Minigame Hub entrance.

Interactions should be functional even if visuals are temporary.

### Phase 2: Care And Hatching Loop

Implement care state, growth state, save data, save/load, offline progress, hatch-ready state, and hatching transition.

### Phase 3: Shell Pudding

Implement the pet stage, intimacy levels, action unlocks, and `creature_animator.gd` action names. Use procedural animation for MVP feedback.

### Phase 4: Bubble Survivor

Implement Minigame Hub, Bubble Survivor, player movement, automatic bubble attack, simple enemies, win/loss conditions, and return-to-island result animation.

## Verification

Pet appearance customization is specified separately in [Face Customization Module](2026-09-10-face-customization-design.md). It changes appearance only and preserves the care and minigame boundaries in this document.

MVP verification should confirm:

- Core state values remain within bounds.
- Offline progress applies safely and does not create harsh punishment.
- The egg can reach hatch-ready state and hatch into Shell Pudding.
- Save/load preserves current stage, states, hatch progress, intimacy, and object state.
- The main island stays clean and interactable in mobile landscape layout.
- The Minigame Hub entrance is visible or clearly discoverable from the main island.
- Bubble Survivor returns only win or loss and does not alter care progression or resources.
- Result animations play correctly after returning from the minigame.
