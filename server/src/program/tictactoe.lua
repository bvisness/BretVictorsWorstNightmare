-- local ar = require("ar")

function ARInit()
  ar.setdata("board", {
    "x", "", "x",
    "", "o", "",
    "x", "", "x",
  })
  ar.setdata("turn", "x")
end

function ARRenderScene()
  local data = ar.getdata()
  local tapped = ar.gettapped()

  if tapped then
    local idx = tonumber(tapped:sub(-1))
    if data.board[idx] ~= "" then
      ar.setdata("board", idx, data.turn)
      if data.turn == "x" then
        ar.setdata("turn", "o")
      else
        ar.setdata("turn", "x")
      end
    end
  end

  pprint(data)
  pprint(data.board)
  local cells = {}
  for i, y in ipairs({ -1, 0, 1 }) do
    for j, x in ipairs({ -1, 0, 1 }) do
      local idx = (i-1) * 3 + j
      table.insert(cells, { type = "triggerbox", id = "cell"..idx, pos = { x * 0.24, y * 0.24, 0 }, size = { 0.24, 0.24, 0.01 } })
      local contents = data.board[idx]
      if contents ~= "" then
        table.insert(cells, { type = "text", text = contents, pos = { x * 0.24 - 0.06, y * 0.24 - 0.10, 0 }, size = 0.20 })
      end
    end
  end

  return {
    { pos = { 0, 0.5, 0 },
      { type = "box", pos = { -0.12, 0, 0 }, size = { 0.02, 0.72, 0.01 } },
      { type = "box", pos = { 0.12, 0, 0 }, size = { 0.02, 0.72, 0.01 } },
      { type = "box", pos = { 0, -0.12, 0 }, size = { 0.72, 0.02, 0.01 } },
      { type = "box", pos = { 0, 0.12, 0 }, size = { 0.72, 0.02, 0.01 } },
      cells,
    }
  }
end
