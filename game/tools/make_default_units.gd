extends SceneTree

## 기본 병종 리소스를 만든다(없을 때만 — 이미 있으면 사용자가 인스펙터에서 고친 값이므로 건드리지 않는다).
##   Godot --headless --path <프로젝트> --script res://game/tools/make_default_units.gd [-- --force]
## 만드는 것: game/units/kar98k.tres(무기) · rifleman_motions.tres(동작 표) · rifleman.tres(병종)

const DIR := "res://game/units"


func _init() -> void:
	var force := OS.get_cmdline_user_args().has("--force")
	DirAccess.make_dir_recursive_absolute(DIR)

	var weapon_path := DIR.path_join("kar98k.tres")
	var weapon: WeaponData
	if force or not ResourceLoader.exists(weapon_path):
		weapon = WeaponData.new()
		weapon.display_name = "Kar98k"
		weapon.range_m = 26.0
		weapon.aim_time = 0.6
		weapon.fire_interval = 1.5
		weapon.mag_size = 5
		weapon.reload_time = 3.0
		weapon.bullet_speed = 400.0
		weapon.damage = 60.0
		weapon.spread_deg = 1.6
		weapon.spread_per_shot_deg = 0.4
		weapon.spread_recover_deg = 1.2
		weapon.suppress_power = 0.3
		weapon.suppress_radius_m = 1.2
		_save(weapon, weapon_path)
	weapon = load(weapon_path) as WeaponData

	var motions_path := DIR.path_join("rifleman_motions.tres")
	var motions: MotionTable
	if force or not ResourceLoader.exists(motions_path):
		motions = MotionTable.new()
		# 세트 stand · crouch · prone 에 구울 동작(뼈대_구조.md "세트별 구울 동작"). 아직 안 구운 동작은 건너뛰고
		# 덜 구체적인 것으로 내려가므로 미리 적어 둬도 된다(상태 이름은 MotionTable.all_keys())
		var m: Dictionary[String, String] = {
			"서기": "Idle", "걷기": "Walk_With_Rifle","달리기": "Sprint",
			"서기+조준": "Rifle_Aiming_Idle", "서기+사격": "Firing_Rifle", "서기+장전": "Stand_Reloading",
			"서기+투척": "Toss_Grenade", "피격": "Idle_Hit", "사망": "Stand_Rifle_Hit_To_Back",
			"앉기": "Crouch_Idle", "앉아걷기": "Crouch_Fwd",
			"앉기+조준": "Crouch_Idle+Rifle_Aiming_Idle", "앉기+사격": "Crouch_Idle+Firing_Rifle",
			"앉기+장전": "Crouch_Reload", "앉기+투척": "Crouch_Idle+Toss_Grenade",
			"피격+앉기": "Crouch_Hit", "사망+앉기": "Crouch_Rifle_Kneel_Hit_To_Back",
			"엎드림": "Crawl_Idle", "포복": "Crawl_Fwd",
			"엎드림+조준": "Prone_Firing_Rifle", "엎드림+사격": "Prone_Firing_Rifle", "엎드림+투척": "Prone_Throw_Grenade",
			"피격+엎드림": "Rifle_Prone_Hit_Reaction", "사망+엎드림": "Prone_Death",
		}
		motions.motions = m
		_save(motions, motions_path)
	motions = load(motions_path) as MotionTable

	var type_path := DIR.path_join("rifleman.tres")
	if force or not ResourceLoader.exists(type_path):
		var t := SoldierType.new()
		t.display_name = "소총수"
		t.squad_size = 6
		t.weapon = weapon
		t.motions = motions
		t.sets_json = "res://puppet/sets.json"
		t.outfit_json = "res://outfits/uniform_m36/outfit.json"
		_save(t, type_path)
	print("UNITS DONE ", DIR)
	quit()


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	print("  %s  %s" % ["저장" if err == OK else "실패(%d)" % err, path])
