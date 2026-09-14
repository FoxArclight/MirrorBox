extends Control

var tool := "land"
var mirror_orientation := "slash"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(32, 30)

func _draw() -> void:
	var c := size * 0.5
	var r := Rect2(c - Vector2(13, 13), Vector2(26, 26))
	match tool:
		"land":
			draw_rect(r, Color("#e6d8b8"))
			draw_line(r.position + Vector2(4, 19), r.end - Vector2(4, 19), Color("#b5a078"), 2)
		"water":
			draw_rect(r, Color("#22527a"))
			for y in [8, 18]:
				draw_line(r.position + Vector2(3, y), r.position + Vector2(23, y - 3), Color("#76c8de"), 2)
		"wall":
			draw_rect(r, Color("#263f56"))
			draw_rect(r, Color("#7290a7"), false, 2)
			draw_line(c - Vector2(12, 0), c + Vector2(12, 0), Color("#7290a7"), 2)
		"crate":
			draw_rect(r, Color("#a8673c"))
			draw_rect(r, Color("#f2bd75"), false, 2)
			draw_line(r.position + Vector2(3, 3), r.end - Vector2(3, 3), Color("#f2bd75"), 3)
			draw_line(r.position + Vector2(23, 3), r.position + Vector2(3, 23), Color("#f2bd75"), 3)
		"mirror":
			draw_rect(r, Color("#4aa9c988"))
			draw_rect(r, Color("#d9fbff"), false, 2)
			var a := Vector2(10, -10) if mirror_orientation == "slash" else Vector2(-10, -10)
			draw_line(c + a, c - a, Color.WHITE, 3)
		"player":
			draw_circle(c, 13, Color("#f26985"))
			draw_circle(c + Vector2(-4, -3), 2, Color.WHITE)
			draw_circle(c + Vector2(4, -3), 2, Color.WHITE)
		"goal":
			draw_rect(r, Color("#503b45"))
			for a in [Vector2(-11, -11), Vector2(11, -11), Vector2(11, 11), Vector2(-11, 11)]:
				var b := Vector2(-a.y, a.x)
				draw_dashed_line(c + a, c + b, Color("#ffe58c"), 2, 4)
		"exit":
			draw_rect(Rect2(c - Vector2(10, 13), Vector2(20, 26)), Color("#24535a"))
			draw_rect(Rect2(c - Vector2(10, 13), Vector2(20, 26)), Color("#8ce4bb"), false, 2)
			draw_circle(c + Vector2(5, 1), 2, Color("#ffe58c"))
		"text":
			draw_rect(r, Color("#2d4564"))
			draw_rect(r, Color("#9ed8e2"), false, 2)
			draw_string(ThemeDB.fallback_font, c + Vector2(-9, 9), "A", HORIZONTAL_ALIGNMENT_CENTER, 18, 25, Color("#f5fbff"))
		"erase":
			draw_line(r.position + Vector2(3, 3), r.end - Vector2(3, 3), Color("#ff7f88"), 4)
			draw_line(r.position + Vector2(23, 3), r.position + Vector2(3, 23), Color("#ff7f88"), 4)
