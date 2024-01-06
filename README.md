# Godot: Stair-stepping Demo
A demonstration of character stair-stepping without using Separation Rays.

Utilizes raycasts and body_test_moves to get step heights, avoid walls, avoid steep slopes, and translate the player up a step.

Note that this uses Jolt Physics (https://github.com/godot-jolt/godot-jolt) instead of the default Godot Physics. While Godot Physics works, there are a few minor issues with player collisions that cause jittering and prevent players from moving in certain circumstances (see notes in player controller script). Jolt Physics is not observed to have these issues, and is preferred.

Controls:

WASD - Movement

Space - Jump (press), Fly (hold)

ESC - Mouse capture toggle

~ / Tilde - Debug menu toggle

Features:
- Stair-stepping with customizable step height
- Basic first-person camera smoothing
- Cool test map

You can install by downloading and importing the addon folder into your Godot project, or by installing from the asset library.

To enable the debug view for collisions, go to the top bar, click "Debug", and enable "Visible Collision Shapes".

Video demonstration: https://www.youtube.com/watch?v=FjD-Ndx8mBk

Finally, beware! This is pretty hacky (well, i think it is anyways)!
