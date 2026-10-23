class_name EventBus
extends RefCounted
## Signal bus for presentation. Gameplay state changes happen in the authority layer
## (Game and friends); UI, audio and effects listen here and never mutate state.
## Owned by Game and injected where needed, so there are no globals and every
## Game instance (a test, a headless server) has its own.

signal player_spawned(player_id: int)
signal player_removed(player_id: int)
## True while a UI element (such as the dev console) wants the mouse and keyboard.
signal ui_capture_changed(ui_has_focus: bool)
