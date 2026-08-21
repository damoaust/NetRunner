extends SceneTree

# One-off headless authoring pass: creates the static mission library as
# res://data/missions/*.tres files. Each mission references a real, reachable
# subnet + exact coordinate / file name (verified by scan_mission_targets.gd
# and the city-grid wiring). Idempotent: overwrites existing files.

const MISSIONS_DIR := "res://data/missions/"
const MissionScript := preload("res://scripts/resources/cp2020_mission.gd")

func _init() -> void:
	var d := DirAccess.open("res://data")
	if d == null:
		print("ERROR: cannot open res://data")
		quit()
		return
	if not d.dir_exists("missions"):
		d.make_dir("missions")

	var missions := [
		{
			"id": "dh_cityhall_schematics", "file": "mission_dh_cityhall_schematics.tres",
			"title": "City Hall Schematics Heist",
			"desc": "City Hall's old mainframe still hosts the original architectural schematics of the Night City municipal vault. Break in, copy the file labelled \"Corporate Schematics\", and bring it back. The file sits on a memory unit deep in the datafort.",
			"type": MissionScript.MissionType.DATA_HARVEST, "reward": 1500,
			"loc": "Night City: City Hall", "subnet": "res://scenes/forts/night_city_subnet.tres",
			"coord": Vector2i(-1, -1), "file_name": "Corporate Schematics",
			"summary": "Steal \"Corporate Schematics\" from City Hall",
		},
		{
			"id": "dh_cityhall_blackmail", "file": "mission_dh_cityhall_blackmail.tres",
			"title": "Blackmail Drop Recovery",
			"desc": "A fixer needs the \"Blackmail Files\" cached on City Hall's memory units before a rival crew fences them. Dive in, copy the file, jack out clean, and hand it to me.",
			"type": MissionScript.MissionType.DATA_HARVEST, "reward": 1200,
			"loc": "Night City: City Hall", "subnet": "res://scenes/forts/night_city_subnet.tres",
			"coord": Vector2i(-1, -1), "file_name": "Blackmail Files",
			"summary": "Steal \"Blackmail Files\" from City Hall",
		},
		{
			"id": "dh_cityhall_passwords", "file": "mission_dh_cityhall_passwords.tres",
			"title": "Stolen Passwords Run",
			"desc": "NetWatch wants a list of stolen passwords traced back to a City Hall terminal. Grab the file named \"Stolen Passwords\" off the memory unit and deliver it.",
			"type": MissionScript.MissionType.DATA_HARVEST, "reward": 1800,
			"loc": "Night City: City Hall", "subnet": "res://scenes/forts/night_city_subnet.tres",
			"coord": Vector2i(-1, -1), "file_name": "Stolen Passwords",
			"summary": "Steal \"Stolen Passwords\" from City Hall",
		},
		{
			"id": "dh_piratebbs_voice", "file": "mission_dh_piratebbs_voice.tres",
			"title": "Pirate BBS Voice Sample",
			"desc": "A blackmailer is hawking a voice recording on the Pirate BBS node. Copy the \"Blackmail Voice Recording\" file and bring it back so we can scrub it.",
			"type": MissionScript.MissionType.DATA_HARVEST, "reward": 1000,
			"loc": "Night City: Pirate BBS", "subnet": "res://scenes/forts/p2.tres",
			"coord": Vector2i(-1, -1), "file_name": "Blackmail Voice Recording",
			"summary": "Steal \"Blackmail Voice Recording\" from Pirate BBS",
		},
		{
			"id": "sab_arasaka_cpu", "file": "mission_sab_arasaka_cpu.tres",
			"title": "Arasaka CPU Strike",
			"desc": "Arasaka's Tokyo-built arcology mainframe is running an intrusive trace program. Crash the CPU at grid (11,11) inside the datafort to take it offline. Use a Krash anti-system program on the exact node.",
			"type": MissionScript.MissionType.SABOTAGE, "reward": 2000,
			"loc": "Night City: Arasaka Arcology", "subnet": "res://scenes/forts/tokyo_subnet.tres",
			"coord": Vector2i(11, 11), "file_name": "",
			"summary": "Crash the CPU at (11,11) in Arasaka Arcology",
		},
		{
			"id": "sab_london_netwatch", "file": "mission_sab_london_netwatch.tres",
			"title": "London NetWatch Crack",
			"desc": "A NetWatch hub in London is coordinating a city-wide sweep. Hit the CPU at grid (12,5) and crash it with an anti-system program to blind them for the night.",
			"type": MissionScript.MissionType.SABOTAGE, "reward": 2200,
			"loc": "London: NetWatch Hub", "subnet": "res://scenes/forts/london_subnet.tres",
			"coord": Vector2i(12, 5), "file_name": "",
			"summary": "Crash the CPU at (12,5) in London",
		},
		{
			"id": "sab_ebm_mainframe", "file": "mission_sab_ebm_mainframe.tres",
			"title": "EBM Mainframe Hit",
			"desc": "EBM's regional mainframe is the bottleneck for a rival corp's payroll run. Crash the CPU at grid (9,4) inside the EBM datafort to halt processing.",
			"type": MissionScript.MissionType.SABOTAGE, "reward": 1500,
			"loc": "Night City: EBM", "subnet": "res://scenes/forts/fort2.tres",
			"coord": Vector2i(9, 4), "file_name": "",
			"summary": "Crash the CPU at (9,4) in EBM",
		},
		{
			"id": "recon_lucky7", "file": "mission_recon_lucky7.tres",
			"title": "Survey Lucky 7 Mall",
			"desc": "A client wants the layout of the Lucky 7 Mall datafort verified. Reach grid (6,6) inside the datafort and confirm the control node is active. No need to crack anything — just get eyes on the target.",
			"type": MissionScript.MissionType.RECON, "reward": 600,
			"loc": "Night City: Lucky 7 Mall", "subnet": "res://scenes/forts/fort1.tres",
			"coord": Vector2i(6, 6), "file_name": "",
			"summary": "Reach grid (6,6) in Lucky 7 Mall",
		},
		{
			"id": "recon_pr0n_core", "file": "mission_recon_pr0n_core.tres",
			"title": "Probe Pr0n Palace Core",
			"desc": "Map the central control node of the Pr0n Palace datafort. Step onto grid (20,6) to complete the survey and jack out.",
			"type": MissionScript.MissionType.RECON, "reward": 800,
			"loc": "Night City: Pr0n Palace", "subnet": "res://scenes/forts/pr0n1.tres",
			"coord": Vector2i(20, 6), "file_name": "",
			"summary": "Reach grid (20,6) in Pr0n Palace",
		},
		{
			"id": "recon_tokyo_mem", "file": "mission_recon_tokyo_mem.tres",
			"title": "Tokyo Memory Scan",
			"desc": "Arasaka's Tokyo subnet holds a memory bank at grid (10,10). Get a runner on that tile to scan the storage layout and report back.",
			"type": MissionScript.MissionType.RECON, "reward": 700,
			"loc": "Night City: Arasaka Arcology", "subnet": "res://scenes/forts/tokyo_subnet.tres",
			"coord": Vector2i(10, 10), "file_name": "",
			"summary": "Reach grid (10,10) in Arasaka Arcology",
		},
	]

	var count := 0
	for spec in missions:
		var m = MissionScript.new()
		m.mission_id = spec["id"]
		m.title = spec["title"]
		m.description = spec["desc"]
		m.mission_type = spec["type"]
		m.reward_credits = spec["reward"]
		m.target_location_label = spec["loc"]
		m.target_subnet_path = spec["subnet"]
		m.target_coord = spec["coord"]
		m.target_file_name = spec["file_name"]
		m.objective_summary = spec["summary"]
		var path: String = MISSIONS_DIR + String(spec["file"])
		var err := ResourceSaver.save(m, path)
		if err != OK:
			print("ERROR saving %s: %d" % [path, err])
		else:
			count += 1
			print("  saved: %s" % path)
	print("Authoring complete: %d mission(s)." % count)
	quit()