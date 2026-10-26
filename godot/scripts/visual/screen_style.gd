extends RefCounted
## Runtime screen presets. Shader globals also cover actors spawned after switching.

const IDS := ["soft", "warm", "moon", "toon", "toon_strong", "toon_outline", "neon_moon", "midnight_magic", "toon_neon", "toon_midnight", "original"]
const NAMES := ["부드러운 명암", "따뜻한 산장", "차가운 숲", "툰 셰이딩", "강렬한 툰 셰이딩", "두꺼운 툰 외곽선", "네온 달빛", "심야 마법", "강렬한 툰 · 네온", "강렬한 툰 · 심야", "기존 화면"]
const DEFAULT_ID := "toon_midnight"
static var current_id := DEFAULT_ID

static func profile(id: String) -> Dictionary:
	var p := {
		"ambient": .42, "moon": .88, "ambient_color": Color(.65,.69,.93),
		"moon_color": Color(.94,.92,1.0), "glow": .22, "ao": 1.0, "ao_radius": .85,
		"shadow_blur": 1.1, "angular": 1.4, "shadow_opacity": .90,
		"shading": Vector4(.58,.065,.08,0.0),
		"surface": Vector4(.28,.60,.65,.075),
		"palette": Vector4(1,1,1,.10), "saturation": 1.0,
		"warm_ground": 1.0, "ink": Vector4(.16,1,0,0), "outline_width": 0.0,
		"rig_energy": 0.0, "haze_opacity": 0.0,
		"magenta_color": Color(1.0,.08,.52), "cyan_color": Color(.16,.48,1.0),
		"ground_emission": .44, "ground_albedo": .62, "ground_neutral": 0.0,
		"ground_tint": Color.WHITE, "vignette": .10, "glow_threshold": 1.0
	}
	match id:
		"warm":
			p.merge({"ambient": .46, "moon": .84, "moon_color": Color(1.0,.96,.91),
				"glow": .30, "shading": Vector4(.48,.085,.12,0),
				"palette": Vector4(1.04,1.01,.97,.18), "warm_ground": 1.10}, true)
		"moon":
			p.merge({"ambient": .34, "moon": .94, "ambient_color": Color(.58,.64,.91),
				"moon_color": Color(.86,.92,1.0), "glow": .18,
				"shading": Vector4(.68,.055,.05,0), "surface": Vector4(.32,.62,.55,.10),
				"palette": Vector4(.97,1.01,1.04,.06), "warm_ground": .90}, true)
		"toon":
			p.merge({"ambient": .27, "moon": 1.05, "glow": .12,
				"ao": .65, "ao_radius": .65, "angular": .9, "shadow_blur": .9,
				"shading": Vector4(1.0,.018,.015,1.0),
				"surface": Vector4(.72,.85,.40,.22), "palette": Vector4(1.02,1.02,1.02,.16),
				"saturation": 1.06}, true)
		"original":
			p.merge({"ambient": .65, "moon": .60, "glow": .55, "ao": 1.8,
				"ao_radius": 1.4, "angular": 2.5, "shadow_blur": 1.6, "shadow_opacity": .85,
				"shading": Vector4(0,.065,.32,0), "surface": Vector4(1,1,1,0),
				"palette": Vector4(1,1,1,0)}, true)
		"toon_strong", "toon_outline":
			p.merge({"ambient": .12, "moon": 1.16, "glow": .06,
				"ao": .45, "ao_radius": .55, "angular": .45, "shadow_blur": .65,
				"shading": Vector4(1,.005,0,1), "surface": Vector4(1,1,.10,.32),
				"palette": Vector4(1.04,1.02,1.04,.22), "saturation": 1.17,
				"ink": Vector4(.035,.45,0,0),
				"outline_width": 3.0 if id == "toon_outline" else 0.0}, true)
		"neon_moon":
			p.merge({"ambient": .23, "moon": .72,
				"ambient_color": Color(.36,.40,.82), "moon_color": Color(.57,.69,1.0),
				"glow": .30, "glow_threshold": 1.15, "ao": .95, "ao_radius": .75,
				"angular": 1.6, "shadow_blur": 1.2, "shadow_opacity": .92,
				"shading": Vector4(.85,.045,.06,0), "surface": Vector4(.70,.80,.22,.16),
				"palette": Vector4(.96,.98,1.08,.12), "ink": Vector4(.10,.45,0,0),
				"saturation": 1.08, "warm_ground": .65, "vignette": .18,
				"rig_energy": 1.0, "haze_opacity": .10,
				"ground_emission": .12, "ground_albedo": .85, "ground_neutral": .35,
				"ground_tint": Color(.88,.95,1.14)}, true)
		"midnight_magic":
			p.merge({"ambient": .12, "moon": .45,
				"ambient_color": Color(.27,.26,.65), "moon_color": Color(.48,.59,1.0),
				"glow": .38, "glow_threshold": 1.15, "ao": 1.10, "ao_radius": .85,
				"angular": .85, "shadow_blur": .90, "shadow_opacity": .96,
				"shading": Vector4(.95,.022,.02,1), "surface": Vector4(.85,.90,.12,.23),
				"palette": Vector4(.97,.93,1.12,.18), "ink": Vector4(.08,.40,0,0),
				"saturation": 1.12, "warm_ground": .48, "vignette": .28,
				"rig_energy": 1.35, "haze_opacity": .075,
				"magenta_color": Color(1.0,.045,.40), "cyan_color": Color(.08,.40,1.0),
				"ground_emission": .055, "ground_albedo": .90, "ground_neutral": .42,
				"ground_tint": Color(.79,.84,1.10)}, true)
		"toon_neon", "toon_midnight":
			# Keep strong toon's exact two-tone, snow/foliage, fill and texture settings.
			# Only the broad lighting and ground atmosphere change. Local falloff remains smooth.
			p = profile("toon_strong")
			p.merge({"ambient": .14, "moon": 1.02,
				"ambient_color": Color(.40,.42,.76), "moon_color": Color(.82,.88,1.0),
				"glow": .18, "glow_threshold": 1.65, "shadow_opacity": .93,
				"palette": Vector4(1.02,1.01,1.06,.22), "saturation": 1.12,
				"warm_ground": .72, "vignette": .15, "rig_energy": .80, "haze_opacity": .05,
				"ground_emission": .12, "ground_albedo": .80, "ground_neutral": .30,
				"ground_tint": Color(.96,.98,1.06)}, true)
			if id == "toon_midnight":
				p.merge({"ambient": .085, "moon": .82,
					"ambient_color": Color(.32,.30,.68), "moon_color": Color(.69,.76,1.0),
					"glow": .24, "glow_threshold": 1.45, "shadow_opacity": .96,
					"warm_ground": .55, "vignette": .24, "rig_energy": 1.05, "haze_opacity": .035,
					"ground_emission": .075, "ground_albedo": .85, "ground_neutral": .38,
					"ground_tint": Color(.88,.90,1.06),
					"magenta_color": Color(1.0,.045,.40), "cyan_color": Color(.10,.42,1.0)}, true)
	return p

static func apply(world, id: String) -> bool:
	if id not in IDS: return false
	current_id = id
	var p := profile(id)
	RenderingServer.global_shader_parameter_set("card_style_shading", p.shading)
	RenderingServer.global_shader_parameter_set("card_style_surface", p.surface)
	RenderingServer.global_shader_parameter_set("card_style_palette", p.palette)
	RenderingServer.global_shader_parameter_set("card_style_ink", p.ink)
	world.outline_mesh.visible = p.outline_width > 0.0
	world.outline_mat.set_shader_parameter("width_pixels", p.outline_width)
	world.env.ssao_radius = p.ao_radius
	world.env.ssao_intensity = p.ao
	world.env.ssao_power = 1.4 if id == "original" else 1.2
	apply_environment(world, p)
	if world.get("day_cycle") != null:
		world.day_cycle.mark_dirty()   # 밤 기준 프로필을 깔았으니 시각 조명을 다음 프레임에 다시 얹게 한다
	return true

static func apply_environment(world, p: Dictionary) -> void:
	# Time of day changes lighting only; toon bands and camera remain independent.
	world.env.ambient_light_color = p.ambient_color
	world.env.ambient_light_energy = p.ambient
	world.sun.light_color = p.moon_color
	world.sun.light_energy = p.moon
	world.sun.shadow_opacity = p.shadow_opacity
	world.sun.shadow_blur = p.shadow_blur
	world.sun.light_angular_distance = p.angular
	world.env.glow_intensity = p.glow
	world.env.glow_hdr_threshold = p.glow_threshold
	world.ground_mat.set_shader_parameter("warm_enabled", p.warm_ground)
	world.ground_mat.set_shader_parameter("ground_emission", p.ground_emission)
	world.ground_mat.set_shader_parameter("ground_albedo", p.ground_albedo)
	world.ground_mat.set_shader_parameter("ground_neutral", p.ground_neutral)
	world.ground_mat.set_shader_parameter("ground_tint", p.ground_tint)
	world.post_mat.set_shader_parameter("saturation", p.saturation)
	world.post_mat.set_shader_parameter("vignette_strength", p.vignette)
	world.reference_lighting.configure(p)
