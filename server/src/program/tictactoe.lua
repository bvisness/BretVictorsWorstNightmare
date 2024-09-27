-- local ar = require("ar")

function ARInit()
  ar.setdata("board", {
    "", "", "",
    "", "", "",
    "", "", "",
  })
  ar.setdata("turn", "x")
end

function ARRenderScene()
  return {
    { type = "box", pos = { -0.12, 0, 0 }, size = { 0.02, 0.72, 0.01 } },
    { type = "box", pos = { 0.12, 0, 0 }, size = { 0.02, 0.72, 0.01 } },
    { type = "box", pos = { 0, -0.12, 0 }, size = { 0.72, 0.02, 0.01 } },
    { type = "box", pos = { 0, 0.12, 0 }, size = { 0.72, 0.02, 0.01 } },
  }
end
