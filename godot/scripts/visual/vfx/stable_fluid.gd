extends RefCounted
## Jos Stam "Stable Fluids"(SIGGRAPH 1999) / "Real-Time Fluid Dynamics for Games"(GDC 2003)의 2D 격자 해법.
## 속도(u,v)·밀도·온도를 (nx+2)×(ny+2) 격자(가장자리 1칸은 경계)에 두고 한 단계마다
##   속도 이류(반-라그랑주) → 힘(온도 부력·바람·와도 보존) → 압력 투영(비압축성)
##   → 밀도·온도 이류 → (확산) → 감쇠
## 순서로 푼다. 반-라그랑주 이류와 투영 덕분에 dt 가 커도 터지지 않는다(무조건 안정).
## 연기다운 소용돌이를 위해 Fedkiw·Stam·Jensen(2001)의 와도 보존과 온도 부력을 더했다.
## 경계: 바닥은 벽이고 굴뚝 입구 칸만 유입구, 위·양옆은 열린 경계(연기가 빠져나가고 옆 공기가 빨려 들어옴).
## 단위: 길이 = 칸, 시간 = 초. 인덱스 k = i + w*j (j=0 이 바닥 경계 줄).

const B_DENS := 0
const B_U := 1
const B_V := 2
const B_PRESSURE := 3
const B_TEMP := 4

var nx: int
var ny: int
var w: int
var size: int

var u := PackedFloat32Array()
var v := PackedFloat32Array()
var dens := PackedFloat32Array()
var temp := PackedFloat32Array()
var pressure := PackedFloat32Array()   # 다음 단계 투영의 초기값으로 재사용(warm start)
## 바닥 경계의 유입구(굴뚝 입구). 칸 i 마다 위쪽 속도·옆 속도·밀도·온도. 위쪽 속도 0 인 칸은 벽.
var inflow_v := PackedFloat32Array()
var inflow_u := PackedFloat32Array()
var inflow_d := PackedFloat32Array()
var inflow_t := PackedFloat32Array()
## 고체 칸(굴뚝 연도 벽 등). 속도·연기 0, 압력은 이웃 유체 칸 값(근사 노이만 경계).
var solid_cells := PackedInt32Array()

var iterations := 12         # 압력 Gauss-Seidel(SOR) 반복 횟수
var sor := 1.65              # 과이완 계수(1 = 순수 Gauss-Seidel)
var diffusion := 0.0         # 밀도 확산 계수(칸²/초)
var vorticity := 1.6         # 와도 보존 세기
var buoyancy := 9.0          # 온도 1 당 위쪽 가속(칸/초²)
var weight := 0.6            # 밀도 1 당 아래쪽 가속(무거운 그을음)
var cooling := 0.55          # 초당 온도 감소 비율
var dissipation := 0.12      # 초당 밀도 감소 비율
var wind := 0.0              # 바람 목표 수평 속도(칸/초). 위로 갈수록 세게 적용
var wind_rate := 0.9         # 바람으로 끌려가는 빠르기(1/초)


func _init(cells_x: int, cells_y: int) -> void:
	nx = cells_x
	ny = cells_y
	w = nx + 2
	size = w * (ny + 2)
	u = _zeros(size)
	v = _zeros(size)
	dens = _zeros(size)
	temp = _zeros(size)
	pressure = _zeros(size)
	inflow_v = _zeros(w)
	inflow_u = _zeros(w)
	inflow_d = _zeros(w)
	inflow_t = _zeros(w)


static func _zeros(n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	a.fill(0.0)
	return a


func idx(i: int, j: int) -> int:
	return i + w * j


## 바닥의 i0..i1 칸을 굴뚝 입구로 연다: 이 속도로 공기가 들어오며 밀도·열을 싣고 온다.
## 가운데가 가장 빠른 포물선 분포. speed <= 0 이면 입구를 닫는다.
func set_inflow(i0: int, i1: int, speed: float, density: float, heat: float, side := 0.0) -> void:
	inflow_v.fill(0.0)
	inflow_u.fill(0.0)
	inflow_d.fill(0.0)
	inflow_t.fill(0.0)
	if speed <= 0.0:
		return
	var half := maxf(0.5 * float(i1 - i0 + 1), 0.5)
	var mid := 0.5 * float(i0 + i1)
	for i in range(maxi(i0, 1), mini(i1, nx) + 1):
		var r := (float(i) - mid) / (half + 0.5)
		var prof := 1.0 - r * r
		inflow_v[i] = speed * (0.55 + 0.45 * prof)
		inflow_u[i] = side
		inflow_d[i] = density * (0.6 + 0.4 * prof)
		inflow_t[i] = heat


## 칸 (i0..i1, j0..j1) 을 고체로 만든다(연도 벽). 여러 번 불러 영역을 더할 수 있다.
func add_solid(i0: int, i1: int, j0: int, j1: int) -> void:
	for j in range(maxi(j0, 1), mini(j1, ny) + 1):
		for i in range(maxi(i0, 1), mini(i1, nx) + 1):
			var k := i + w * j
			if not solid_cells.has(k):
				solid_cells.append(k)


func _clear_solids(x: PackedFloat32Array) -> PackedFloat32Array:
	for k in solid_cells:
		x[k] = 0.0
	return x


## 고체 칸의 압력 = 이웃 유체 칸 평균. 벽을 가로지르는 압력 기울기가 0 이 되어 흐름이 벽을 통과하지 않는다.
func _solid_pressure(p: PackedFloat32Array) -> PackedFloat32Array:
	for k in solid_cells:
		var s := 0.0
		var n := 0
		for o in [-1, 1, -w, w]:
			if not solid_cells.has(k + o):
				s += p[k + o]
				n += 1
		p[k] = s / n if n > 0 else 0.0
	return p


func step(dt: float) -> void:
	var u_prev := _set_bnd(B_U, u)
	var v_prev := _set_bnd(B_V, v)
	u = _advect(B_U, u_prev, u_prev, v_prev, dt)
	v = _advect(B_V, v_prev, u_prev, v_prev, dt)
	_forces(dt)
	u = _clear_solids(u)
	v = _clear_solids(v)
	_project()
	dens = _clear_solids(_advect(B_DENS, _set_bnd(B_DENS, dens), u, v, dt))
	temp = _clear_solids(_advect(B_TEMP, _set_bnd(B_TEMP, temp), u, v, dt))
	if diffusion > 0.0:
		dens = _diffuse(B_DENS, dens, diffusion, dt)
	var dk := exp(-dissipation * dt)
	var tk := exp(-cooling * dt)
	for k in size:
		dens[k] *= dk
		temp[k] *= tk


## 부력·바람·와도 보존을 속도장에 더한다.
func _forces(dt: float) -> void:
	var curl := _zeros(size)
	for j in range(1, ny + 1):
		for i in range(1, nx + 1):
			var k := i + w * j
			curl[k] = 0.5 * ((v[k + 1] - v[k - 1]) - (u[k + w] - u[k - w]))
	var inv_ny := 1.0 / float(ny)
	for j in range(1, ny + 1):
		# 지붕 위 바람: 굴뚝 바로 위는 가려져 약하고 위로 갈수록 세다.
		var h := float(j) * inv_ny
		var wind_here := wind * (0.25 + 0.75 * minf(h * 1.6, 1.0))
		var wr := minf(wind_rate * dt * (0.3 + 0.7 * h), 1.0)
		for i in range(1, nx + 1):
			var k := i + w * j
			var fx := 0.0
			var fy := buoyancy * temp[k] - weight * dens[k]
			if j > 1 and j < ny and i > 1 and i < nx:
				var c := curl[k]
				var gx := 0.5 * (absf(curl[k + 1]) - absf(curl[k - 1]))
				var gy := 0.5 * (absf(curl[k + w]) - absf(curl[k - w]))
				var gl := sqrt(gx * gx + gy * gy) + 1e-5
				fx += vorticity * (gy / gl) * c
				fy -= vorticity * (gx / gl) * c
			u[k] += fx * dt + (wind_here - u[k]) * wr
			v[k] += fy * dt
	u = _set_bnd(B_U, u)
	v = _set_bnd(B_V, v)


## 압력 투영: 발산을 없애 속도장을 비압축성으로 만든다(Helmholtz–Hodge 분해).
func _project() -> void:
	var div := _zeros(size)
	for j in range(1, ny + 1):
		for i in range(1, nx + 1):
			var k := i + w * j
			div[k] = -0.5 * (u[k + 1] - u[k - 1] + v[k + w] - v[k - w])
	var p := pressure
	var om := sor
	for it in iterations:
		for j in range(1, ny + 1):
			for i in range(1, nx + 1):
				var k := i + w * j
				var gs := (div[k] + p[k - 1] + p[k + 1] + p[k - w] + p[k + w]) * 0.25
				p[k] += om * (gs - p[k])
		p = _set_bnd(B_PRESSURE, p)
		if not solid_cells.is_empty():
			p = _solid_pressure(p)
	pressure = p
	for j in range(1, ny + 1):
		for i in range(1, nx + 1):
			var k := i + w * j
			u[k] -= 0.5 * (p[k + 1] - p[k - 1])
			v[k] -= 0.5 * (p[k + w] - p[k - w])
	u = _clear_solids(u)
	v = _clear_solids(v)
	u = _set_bnd(B_U, u)
	v = _set_bnd(B_V, v)


## 반-라그랑주 이류: 각 칸 중심에서 속도를 거슬러 올라간 자리의 값을 쌍선형 보간해 가져온다.
func _advect(b: int, d0: PackedFloat32Array, uu: PackedFloat32Array, vv: PackedFloat32Array, dt: float) -> PackedFloat32Array:
	var d := _zeros(size)
	var xmax := float(nx) + 0.5
	var ymax := float(ny) + 0.5
	for j in range(1, ny + 1):
		for i in range(1, nx + 1):
			var k := i + w * j
			var x := clampf(float(i) - dt * uu[k], 0.5, xmax)
			var y := clampf(float(j) - dt * vv[k], 0.5, ymax)
			var i0 := int(x)
			var j0 := int(y)
			var s1 := x - float(i0)
			var t1 := y - float(j0)
			var k0 := i0 + w * j0
			d[k] = (1.0 - s1) * ((1.0 - t1) * d0[k0] + t1 * d0[k0 + w]) \
				+ s1 * ((1.0 - t1) * d0[k0 + 1] + t1 * d0[k0 + 1 + w])
	return _set_bnd(b, d)


## 암시적 확산(Stam 의 lin_solve). 계수가 작아 몇 번만 반복해도 수렴한다.
func _diffuse(b: int, x0: PackedFloat32Array, diff: float, dt: float) -> PackedFloat32Array:
	var a := dt * diff
	var c := 1.0 / (1.0 + 4.0 * a)
	var x := x0.duplicate()
	for it in 4:
		for j in range(1, ny + 1):
			for i in range(1, nx + 1):
				var k := i + w * j
				x[k] = (x0[k] + a * (x[k - 1] + x[k + 1] + x[k - w] + x[k + w])) * c
		x = _set_bnd(b, x)
	return x


## 경계: 바닥 벽(수직 속도 반사, 굴뚝 입구는 유입값), 위·양옆 열린 경계(값 복사, 압력은 0).
func _set_bnd(b: int, x: PackedFloat32Array) -> PackedFloat32Array:
	var top := w * (ny + 1)
	for i in range(1, nx + 1):
		var open := inflow_v[i] > 0.0
		match b:
			B_V: x[i] = inflow_v[i] if open else -x[i + w]
			B_U: x[i] = inflow_u[i] if open else x[i + w]
			B_DENS: x[i] = inflow_d[i] if open else 0.0
			B_TEMP: x[i] = inflow_t[i] if open else 0.0
			_: x[i] = x[i + w]
		if b == B_PRESSURE:
			x[top + i] = 0.0
		elif b == B_V:
			x[top + i] = maxf(x[top + i - w], 0.0)   # 위로는 빠져나가기만(되돌아 들어오지 않음)
		else:
			x[top + i] = x[top + i - w]
	for j in range(1, ny + 1):
		var k := w * j
		if b == B_PRESSURE:
			x[k] = 0.0
			x[k + nx + 1] = 0.0
		elif b == B_DENS or b == B_TEMP:
			x[k] = 0.0
			x[k + nx + 1] = 0.0
		else:
			x[k] = x[k + 1]
			x[k + nx + 1] = x[k + nx]
	x[0] = 0.5 * (x[1] + x[w])
	x[nx + 1] = 0.5 * (x[nx] + x[nx + 1 + w])
	x[top] = 0.5 * (x[top + 1] + x[top - w])
	x[top + nx + 1] = 0.5 * (x[top + nx] + x[top - w + nx + 1])
	return x


# ───────────── 검증·진단용 ─────────────

func total_density() -> float:
	var s := 0.0
	for j in range(1, ny + 1):
		for i in range(1, nx + 1):
			s += dens[i + w * j]
	return s


## 밀도 가중 무게중심(칸 좌표).
func density_centroid() -> Vector2:
	var s := 0.0
	var c := Vector2.ZERO
	for j in range(1, ny + 1):
		for i in range(1, nx + 1):
			var d := dens[i + w * j]
			s += d
			c += Vector2(i, j) * d
	return c / s if s > 1e-6 else Vector2.ZERO


## 내부 칸의 |발산| 평균과 최댓값. 투영 직후 값이 작아야 한다.
func divergence_stats() -> Vector2:
	var m := 0.0
	var s := 0.0
	for j in range(1, ny + 1):
		for i in range(1, nx + 1):
			var k := i + w * j
			var d := absf(0.5 * (u[k + 1] - u[k - 1] + v[k + w] - v[k - w]))
			s += d
			m = maxf(m, d)
	return Vector2(s / float(nx * ny), m)


func max_speed() -> float:
	var m := 0.0
	for k in size:
		m = maxf(m, u[k] * u[k] + v[k] * v[k])
	return sqrt(m)


func all_finite() -> bool:
	for k in size:
		if not (is_finite(u[k]) and is_finite(v[k]) and is_finite(dens[k]) and is_finite(temp[k])):
			return false
	return true


