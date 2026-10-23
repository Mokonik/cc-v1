#!/usr/bin/env python3
"""Generates the .tres content for monsters, perks and loot from the tables below.

The tables are the single place to read and tune the numbers; the .tres files are what the
game loads (you can also tune them in the Godot inspector, but re-running this overwrites
them). Run: python3 pvpve/tools/make_content.py
"""
import os

ROOT = os.path.join(os.path.dirname(__file__), "..", "content")


def fmt(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return '&"%s"' % value
    if isinstance(value, tuple):
        return "Color(%s)" % ", ".join(str(c) for c in value)
    return str(value)


def write(path, text):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as f:
        f.write(text)
    print("wrote content/" + path)


# ---- monster projectiles (WeaponDef resources; not part of the player's catalog) -----------

def weapon_def(name, **fields):
    lines = ['[gd_resource type="Resource" script_class="WeaponDef" load_steps=2 format=3]', "",
             '[ext_resource type="Script" path="res://game/combat/weapon_def.gd" id="1_def"]', "",
             "[resource]", 'script = ExtResource("1_def")']
    for key, value in fields.items():
        lines.append("%s = %s" % (key, fmt(value)))
    write("monsters/%s.tres" % name, "\n".join(lines) + "\n")


weapon_def("spit", id="spit", display_name="Spit", kind=2, damage=12.0, fire_interval=1.8,
           projectile_speed=20.0, projectile_gravity=4.0, projectile_lifetime=3.0, magazine=0)
weapon_def("boss_orb", id="boss_orb", display_name="Warden Orb", kind=2, damage=16.0, fire_interval=3.0,
           projectile_speed=15.0, projectile_gravity=0.0, projectile_lifetime=4.0, magazine=0)

# ---- monsters -----------------------------------------------------------------------------

MONSTERS = {
    "grunt": dict(id="grunt", display_name="Grunt", radius=0.4, height=1.6, color=(0.55, 0.7, 0.35, 1),
                  max_hp=60.0, move_speed=4.2, melee_damage=10.0, melee_range=1.9, melee_windup=0.35,
                  melee_interval=1.1, score_value=10, xp=20, sabotage_points=1, loot_chance=0.22),
    "spitter": dict(id="spitter", display_name="Spitter", radius=0.35, height=1.5, color=(0.65, 0.4, 0.8, 1),
                    max_hp=40.0, move_speed=3.6, melee_damage=0.0, spit_count=1, spit_spread_deg=0.0,
                    spit_range=24.0, spit_windup=0.5, spit_interval=1.8, keep_distance=14.0,
                    score_value=18, xp=30, sabotage_points=1, loot_chance=0.3, _spit="spit"),
    "brute": dict(id="brute", display_name="Brute", radius=0.65, height=2.2, color=(0.8, 0.4, 0.3, 1),
                  max_hp=160.0, move_speed=2.8, melee_damage=0.0, slam_damage=30.0, slam_radius=2.8,
                  slam_windup=0.7, slam_cooldown=2.4, charge_damage=25.0, charge_windup=0.8,
                  charge_speed=14.0, charge_time=1.2, charge_cooldown=6.0, stun_time=1.5,
                  score_value=40, xp=70, sabotage_points=2, loot_chance=0.5),
    "warden": dict(id="warden", display_name="Warden", radius=1.1, height=3.4, color=(0.25, 0.2, 0.35, 1),
                   max_hp=900.0, move_speed=3.4, melee_damage=0.0, slam_damage=35.0, slam_radius=4.5,
                   slam_windup=0.8, slam_cooldown=3.5, charge_damage=30.0, charge_windup=0.9,
                   charge_speed=15.0, charge_time=1.3, charge_cooldown=7.0, stun_time=1.2,
                   spit_count=3, spit_spread_deg=12.0, spit_range=30.0, spit_windup=0.7, spit_interval=4.0,
                   keep_distance=0.0, summon_id="grunt", summon_count=4, summon_at_fraction=0.5,
                   enrage_fraction=0.35, is_boss=True, score_value=300, xp=400,
                   sabotage_points=8, loot_chance=1.0, sight_range=120.0, _spit="boss_orb"),
}

for name, fields in MONSTERS.items():
    spit = fields.pop("_spit", None)
    lines = ['[gd_resource type="Resource" script_class="MonsterDef" load_steps=%d format=3]' % (3 if spit else 2), "",
             '[ext_resource type="Script" path="res://game/pve/monster_def.gd" id="1_def"]']
    if spit:
        lines.append('[ext_resource type="Resource" path="res://content/monsters/%s.tres" id="2_spit"]' % spit)
    lines += ["", "[resource]", 'script = ExtResource("1_def")']
    for key, value in fields.items():
        lines.append("%s = %s" % (key, fmt(value)))
    if spit:
        lines.append('spit = ExtResource("2_spit")')
    write("monsters/%s.tres" % name, "\n".join(lines) + "\n")

# ---- perks ----------------------------------------------------------------------------------

PERKS = {
    "vitality": dict(display_name="Vitality", description="+15 maximum health.", max_stacks=4, max_hp_bonus=15.0),
    "swiftness": dict(display_name="Swiftness", description="+6% movement speed.", max_stacks=4, speed_bonus=0.06),
    "marksman": dict(display_name="Marksman", description="+8% damage with the pistol, bow and orb.", max_stacks=4,
                     gun_damage_bonus=0.08, bow_damage_bonus=0.08, orb_damage_bonus=0.08),
    "berserker": dict(display_name="Berserker", description="+10% sword damage.", max_stacks=4, melee_damage_bonus=0.10),
    "quick_hands": dict(display_name="Quick Hands", description="12% faster reloads and bow draws.", max_stacks=3,
                        reload_time_reduction=0.12, draw_time_reduction=0.12),
    "pyromancer": dict(display_name="Pyromancer", description="Fire Orb: +0.6 m blast radius and 10% shorter cooldown.",
                       max_stacks=3, orb_radius_bonus=0.6, orb_cooldown_reduction=0.10),
    "iron_skin": dict(display_name="Iron Skin", description="Take 8% less damage.", max_stacks=4, damage_taken_reduction=0.08),
    "second_wind": dict(display_name="Second Wind", description="Heal 6 health whenever you kill something.",
                        max_stacks=3, kill_heal=6.0),
    "scavenger": dict(display_name="Scavenger", description="+8% loot chance and +1 Sabotage Point per kill.",
                      max_stacks=3, loot_chance_bonus=0.08, sabotage_point_bonus=1),
}

for name, fields in PERKS.items():
    lines = ['[gd_resource type="Resource" script_class="PerkDef" load_steps=2 format=3]', "",
             '[ext_resource type="Script" path="res://game/pve/perk_def.gd" id="1_def"]', "",
             "[resource]", 'script = ExtResource("1_def")', 'id = &"%s"' % name]
    for key, value in fields.items():
        lines.append("%s = %s" % (key, '"%s"' % value if isinstance(value, str) else fmt(value)))
    write("perks/%s.tres" % name, "\n".join(lines) + "\n")

# ---- loot -------------------------------------------------------------------------------------
# kind: 0 WEAPON, 1 HEALTH, 2 TRAP, 3 XP

LOOT = [
    dict(kind=1, id="", weight=30.0, min_wave=1, amount=35),
    dict(kind=2, id="", weight=18.0, min_wave=1, amount=0),
    dict(kind=3, id="", weight=22.0, min_wave=1, amount=25),
    dict(kind=0, id="sword", weight=10.0, min_wave=1, amount=0),
    dict(kind=0, id="bow", weight=10.0, min_wave=1, amount=0),
    dict(kind=0, id="orb", weight=8.0, min_wave=2, amount=0),
    dict(kind=0, id="pistol", weight=10.0, min_wave=2, amount=0),
]
lines = ['[gd_resource type="Resource" script_class="LootTable" load_steps=%d format=3]' % (len(LOOT) + 3), "",
         '[ext_resource type="Script" path="res://game/pve/loot_table.gd" id="1_table"]',
         '[ext_resource type="Script" path="res://game/pve/loot_entry.gd" id="2_entry"]', ""]
for i, entry in enumerate(LOOT):
    lines += ['[sub_resource type="Resource" id="Resource_%d"]' % i, 'script = ExtResource("2_entry")']
    for key, value in entry.items():
        lines.append("%s = %s" % (key, fmt(value) if key == "id" else str(value) if not isinstance(value, float) else str(value)))
    lines.append("")
lines += ["[resource]", 'script = ExtResource("1_table")',
          "entries = [%s]" % ", ".join('SubResource("Resource_%d")' % i for i in range(len(LOOT)))]
write("loot/default_loot.tres", "\n".join(lines) + "\n")

# ---- pve config -------------------------------------------------------------------------------
write("pve_config.tres", '''[gd_resource type="Resource" script_class="PveConfig" load_steps=2 format=3]

[ext_resource type="Script" path="res://game/pve/pve_config.gd" id="1_cfg"]

[resource]
script = ExtResource("1_cfg")
''')

# ---- match config -----------------------------------------------------------------------------
write("match_config.tres", '''[gd_resource type="Resource" script_class="MatchConfig" load_steps=2 format=3]

[ext_resource type="Script" path="res://game/match/match_config.gd" id="1_cfg"]

[resource]
script = ExtResource("1_cfg")
''')

# ---- world modifiers ---------------------------------------------------------------------------
MODIFIERS = {
    "double_spawns": dict(display_name="Double Spawns", color=(1.0, 0.54, 0.31, 1),
                          description="Twice the monsters, and 15 points more loot chance on each.",
                          count_mult=2.0, loot_chance_bonus=0.15),
    "elite_monsters": dict(display_name="Elite Monsters", color=(0.95, 0.35, 0.45, 1),
                           description="Monsters have 50% more health and hit 30% harder, and give 50% more XP.",
                           hp_mult=1.5, damage_mult=1.3, xp_mult=1.5),
    "low_gravity": dict(display_name="Low Gravity", color=(0.6, 0.42, 1.0, 1),
                        description="You fall slowly and jump much higher. Arrows and orbs are unchanged.",
                        gravity_mult=0.55),
    "fog": dict(display_name="Fog of War", color=(0.7, 0.75, 0.85, 1),
                description="Thick fog. You see only nearby, and ranged monsters must come close.",
                range_mult=0.5, fog_density=0.045),
    "volatile": dict(display_name="Volatile", color=(1.0, 0.8, 0.2, 1),
                     description="Monsters explode when they die: 20 damage to anyone within 3 m.",
                     volatile_damage=20.0, volatile_radius=3.0),
}
for name, fields in MODIFIERS.items():
    lines = ['[gd_resource type="Resource" script_class="ModifierDef" load_steps=2 format=3]', "",
             '[ext_resource type="Script" path="res://game/match/modifier_def.gd" id="1_def"]', "",
             "[resource]", 'script = ExtResource("1_def")', 'id = &"%s"' % name]
    for key, value in fields.items():
        lines.append("%s = %s" % (key, '"%s"' % value if isinstance(value, str) else fmt(value)))
    write("modifiers/%s.tres" % name, "\n".join(lines) + "\n")
