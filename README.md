# Godot: Stair-stepping Demo
A demonstration of character stair-stepping without using Separation Rays.

While Separation Rays are recommended, they tend to be very buggy with default Godot Physics and do not work at all with the [Jolt Physics Addon](https://github.com/godot-jolt/godot-jolt).
This implementation utilizes the [PhysicsServer3D's body_test_motion](https://docs.godotengine.org/en/stable/classes/class_physicsserver3d.html#class-physicsserver3d-method-body-test-motion) instead to test for collisions using a copy of the player's collision shape, meaning that this is compatible with any collision shape. Along with this, you are able to change how far up the player can step (Max step up) and how far the player can step down (Max step down).

Note that this uses Jolt Physics instead of the default Godot Physics. While Godot Physics works, there are a few minor issues with player collisions that cause jittering and prevent players from moving in certain circumstances (see notes in player controller script). Jolt Physics is not observed to have these issues, and is preferred.

## Controls:
- WASD - Movement
- Space - Jump (press), Fly (hold)
- ESC - Mouse capture toggle
- ~ / Tilde - Debug menu toggle

## Features:
- Stair-stepping with customizable step up and step down heights
- Basic first-person camera smoothing
- Cool test map (objective)

You can install by downloading and importing the addon folder into your Godot project, or by installing from the asset library.

To enable the debug view for collisions, go to the top bar, click "Debug", and enable "Visible Collision Shapes".

Video demonstration: https://www.youtube.com/watch?v=FjD-Ndx8mBk

Finally, very special thank you to [Andicraft](https://github.com/Andicraft) for their help!
