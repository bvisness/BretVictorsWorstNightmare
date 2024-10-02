function ARInit()
  ar.setdata("vecs", { {0.15, 0, 0}, {0, 0.15, 0}, {0, 0, 0.15} })
end

local colors = {"red", "green", "blue"}

function ARRenderScene()
  local vecs = ar.getdata()["vecs"]
  local rendered = {}
  for i, v in ipairs(vecs) do
    local color = colors[((i-1) % #colors) + 1]
    table.insert(rendered, Vec(v, color))
  end
  return rendered
end

function Vec(v, color)
  local len = vlen(v)
  local thickness = 0.01
  local headsize = thickness * 3
  local cylinderlen = len - headsize + thickness
  return {
    rot = { from = {1, 0, 0}, to = v },

    {
      type = "cylinder",
      pos = {cylinderlen/2, 0, 0},
      rot = { axis = {0, 1, 0}, angle = math.pi/2 },
      size = {thickness, thickness, cylinderlen},
      color = color,
    },
    {
      type = "cone",
      pos = {len-(headsize/2), 0, 0},
      rot = { axis = {0, 1, 0 }, angle = math.pi/2 },
      size = headsize,
      color = color,
    },
  }
end

function vlen(v)
  return math.sqrt(v[1]*v[1] + v[2]*v[2] + v[3]*v[3])
end

function vnorm(v)
  local len = vlen(v)
  return { v[1]/len, v[2]/len, v[3]/len }
end

function vcross(a, b)
  return {
    (a[2] * b[3]) - (a[3] * b[2]),
    (a[3] * b[1]) - (a[1] * b[3]),
    (a[1] * b[2]) - (a[2] * b[1]),
  }
end

function vdot(a, b)
  return (a[1] * b[1]) + (a[2] * b[2]) + (a[3] * b[3]);
end
